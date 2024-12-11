local constants = require "kong.constants"
local jwt_decoder = require "kong.plugins.ejwt.jwt_parser"
local kong_meta = require "kong.meta"

local fmt = string.format
local kong = kong
local type = type
local error = error
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local re_gmatch = ngx.re.gmatch


local eJwtHandler = {
  VERSION = kong_meta.version,
  PRIORITY = -1,
}


--- Retrieve a JWT in a request.
-- Checks for the JWT in URI parameters, then in cookies, and finally
-- in the configured header_names (defaults to `[Authorization]`).
-- @param conf Plugin configuration
-- @return token JWT token contained in request (can be a table) or nil
-- @return err
local function retrieve_tokens(conf)
  local token_set = {}
  local args = kong.request.get_query()
  for _, v in ipairs(conf.uri_param_names) do
    local token = args[v] -- can be a table
    if token then
      if type(token) == "table" then
        for _, t in ipairs(token) do
          if t ~= "" then
            token_set[t] = true
          end
        end

      elseif token ~= "" then
        token_set[token] = true
      end
    end
  end

  local var = ngx.var
  for _, v in ipairs(conf.cookie_names) do
    local cookie = var["cookie_" .. v]
    if cookie and cookie ~= "" then
      token_set[cookie] = true
    end
  end

  local request_headers = kong.request.get_headers()
  for _, v in ipairs(conf.header_names) do
    local token_header = request_headers[v]
    if token_header then
      if type(token_header) == "table" then
        token_header = token_header[1]
      end
      local iterator, iter_err = re_gmatch(token_header, "\\s*[Bb]earer\\s+(.+)")
      if not iterator then
        kong.log.err(iter_err)
        break
      end

      local m, err = iterator()
      if err then
        kong.log.err(err)
        break
      end

      if m and #m > 0 then
        if m[1] ~= "" then
          token_set[m[1]] = true
        end
      end
    end
  end

  local tokens_n = 0
  local tokens = {}
  for token, _ in pairs(token_set) do
    tokens_n = tokens_n + 1
    tokens[tokens_n] = token
  end

  if tokens_n == 0 then
    return nil
  end

  if tokens_n == 1 then
    return tokens[1]
  end

  return tokens
end


local function load_credential(jwt_secret_key)
  local row, err = kong.db.jwt_secrets:select_by_key(jwt_secret_key)
  if err then
    return nil, err
  end
  return row
end


local function set_consumer(consumer, credential, token)
  kong.client.authenticate(consumer, credential)

  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if consumer and consumer.id then
    set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  else
    clear_header(constants.HEADERS.CONSUMER_ID)
  end

  if consumer and consumer.custom_id then
    set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  else
    clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  end

  if consumer and consumer.username then
    set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  else
    clear_header(constants.HEADERS.CONSUMER_USERNAME)
  end

  if credential and credential.key then
    set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.key)
  else
    clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
  end

  if credential then
    clear_header(constants.HEADERS.ANONYMOUS)
  else
    set_header(constants.HEADERS.ANONYMOUS, true)
  end

  kong.ctx.shared.authenticated_jwt_token = token -- TODO: wrap in a PDK function?
end


local function do_authentication(conf)
  local token, err = retrieve_tokens(conf)
  if err then
    return error(err)
  end

  local token_type = type(token)
  if token_type ~= "string" then
    if token_type == "nil" then
      return false, { status = 401, message = "Unauthorized" }
    elseif token_type == "table" then
      return false, { status = 401, message = "Multiple tokens provided" }
    else
      return false, { status = 401, message = "Unrecognizable token" }
    end
  end

  -- Decode token to find out who the consumer is
  local jwt, err = jwt_decoder:new(token)
  if err then
    return false, { status = 401, message = "Bad token; " .. tostring(err) }
  end

  local claims = jwt.claims
  local header = jwt.header

  local jwt_secret_key = claims[conf.key_claim_name] or header[conf.key_claim_name]
  if not jwt_secret_key then
    return false, { status = 401, message = "No mandatory '" .. conf.key_claim_name .. "' in claims" }
  elseif jwt_secret_key == "" then
    return false, { status = 401, message = "Invalid '" .. conf.key_claim_name .. "' in claims" }
  end

  local rsa_flag = jwt.header.alg:sub(1, 2) == "RS"
  local max_loop = rsa_flag and conf.max_multi_rsa or 1
  for i = 1, max_loop, 1 do repeat
    local key_suffix = rsa_flag and string.format(conf.key_suffix_format, i-1) or ""
    local jwt_secret_key_enum = jwt_secret_key .. key_suffix

    local jwt_secret_cache_key = kong.db.ejwt_secrets:cache_key(jwt_secret_key_enum)
    local jwt_secret, err      = kong.cache:get(jwt_secret_cache_key, nil,
                                                load_credential, jwt_secret_key_enum)
    if err then
      kong.log.err(fmt("Error occurs at jwt_secret acquiry %s, @ %s", err, jwt_secret_key_enum))
      break
    end
    -- if max_loop = 10, make sure there must be no key hollow between a3fc3049...7243c###00 and a3fc3049...7243c###9
    -- because if no jwt_secret for a3fc3049...7243c###5, it means no jwt_secret for a3fc3049...7243c###6, a3fc3049...7243c###7, ... and further
    if not jwt_secret then
      kong.log.warn(fmt("No credentials found, @ %s", jwt_secret_key_enum))
      return false, { status = 401, message = fmt("No credentials available for given '%s'", conf.key_claim_name) }
    end

    local algorithm = jwt_secret.algorithm or "HS256"
    if jwt.header.alg ~= algorithm then
      kong.log.err(fmt("Secret algorithm mismatch, %s, %s, @ %s", jwt.header.alg, algorithm, jwt_secret_key_enum))
      break
    end
    local jwt_secret_value = algorithm ~= nil and algorithm:sub(1, 2) == "HS" and jwt_secret.secret or jwt_secret.rsa_public_key
    if conf.secret_is_base64 then
      jwt_secret_value = jwt:base64_decode(jwt_secret_value)
    end
    if not jwt_secret_value then
      kong.log.err(fmt("Invalid key/secret value, @ %s", jwt_secret_key_enum))
      break
    end
    if not jwt:verify_signature(jwt_secret_value) then
      kong.log.err(fmt("Invalid signature, @ %s", jwt_secret_key_enum))
      break
    end
    local ok_claims, errors = jwt:verify_registered_claims(conf.claims_to_verify)
    if not ok_claims then
      kong.log.err(fmt("Error occurs at claims verification, %s, @ %s", errors, jwt_secret_key_enum))
      break
    end
    if conf.maximum_expiration ~= nil and conf.maximum_expiration > 0 then
      local ok, errors = jwt:check_maximum_expiration(conf.maximum_expiration)
      if not ok then
        kong.log.err(fmt("Error occurs at expiration check, %s, @ %s", errors, jwt_secret_key_enum))
        break
      end
    end

    local consumer_cache_key = kong.db.consumers:cache_key(jwt_secret.consumer.id)
    local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                              kong.client.load_consumer,
                                              jwt_secret.consumer.id, true)
    if err then
      kong.log.err(fmt("Error occurs at consumers acquiry, %s, @ %s", err, jwt_secret_key_enum))
      break
    end
    if not consumer then
      kong.log.err(fmt("Could not find consumer for '%s = %s'", conf.key_claim_name, jwt_secret_key_enum))
      break
    end
    set_consumer(consumer, jwt_secret, token)
    return true
    -- lua has no continue statement which should be simulated
    -- also lua5.1 doesn't support goto statement
  until true end
  return false, { status = 401, message = fmt("No credentials available for given '%s'", conf.key_claim_name) }
end


local function cache_jwt_secrets()
  local cntr = 0
  for secret, err in kong.db.jwt_secrets:each() do
    if err then
      kong.log.err(fmt("Iterating jwt_secrets exits with exception, %s, %s", err, cntr))
      return
    end
    local secret_key = secret.key
    local secret_cache_key = kong.db.ejwt_secrets:cache_key(secret_key)
    local _, err  = kong.cache:get(secret_cache_key, nil, load_credential, secret_key)
    cntr = cntr + 1
    if err then
      kong.log.err(fmt("Caching jwt_secrets exits with exception, %s, %s", err, cntr))
      return
    end
  end
  kong.log.info(fmt("Caching jwt_secrets exits without exception, %s", cntr))
  return
end


function eJwtHandler:init_worker()
  local worker_id = ngx.worker.id()
  kong.log.info("eJwt init_worker started, ", worker_id)
  -- sync & cache full jwt_secrets at initial stage
  -- limited access jwt_secrets in init_worker stage, should be postponed for several seconds
  ngx.timer.at(16, cache_jwt_secrets)
end


function eJwtHandler:access(conf)
  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
    return
  end

  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous then
      -- get anonymous user
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                                kong.client.load_consumer,
                                                conf.anonymous, true)
      if err then
        return error(err)
      end

      set_consumer(consumer)

    else
      return kong.response.exit(err.status, err.errors or { message = err.message })
    end
  end
end


return eJwtHandler
