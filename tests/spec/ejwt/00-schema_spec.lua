local PLUGIN_NAME = "ejwt"

-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end

describe(PLUGIN_NAME .. ": (schema)", function()
  it("config-schema test: mandatory parameters", function()
    local ok, err = validate({
      cache_redis_host = "mock-redis-host",
      cache_redis_password = "mock-redis-password",
      token_exchange_url = "mock-mxid3-url",
      token_exchange_client_id = "mock-client-id",
      token_exchange_client_secret = "mock-client-secret"
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
end)
