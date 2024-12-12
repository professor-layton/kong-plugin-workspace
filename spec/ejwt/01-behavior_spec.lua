local cjson = require("cjson.safe")
local helpers = require("spec.helpers")

local PLUGIN_NAME = "ejwt"

-- https://github.com/Kong/kong-plugin/issues/38
-- https://github.com/Kong/kong-pongo/issues/303
-- even for dbless test, postgres is still needed. 'postgres' mode first, test-helpers will write to DB whose data will be leveraged by 'off' mode later.

-- by default, all_strategies = {"postgres", "cassandra", "off"}
for _, strategy in helpers.all_strategies()
  -- condition: strategy != "cassandra"
  do if strategy ~= "cassandra" then

    describe(PLUGIN_NAME .. ": (behavior) [#" .. strategy .. "]", function()
      local client
      -- lazy_setup, lazy_teardown:
      -- will only run if there is at least one child test present in the current or any nested describe blocks
      lazy_setup(function()
        -- inject a test route, when "strategy = off" it will still be written to postgres
        local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {"routes","services","plugins","consumers","jwt_secrets"}, { PLUGIN_NAME })
        local route = bp.routes:insert({
          hosts = { "ejwt.kong.com" },
        })
        -- add plugin
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = route.id },
          config = {
            max_multi_rsa = 5
          },
        }
        -- add kong consumer
        local consumer = bp.consumers:insert {
          username = "consumer_0",
        }
        -- add jwt_secrets
        bp.jwt_secrets:insert {
          algorithm = "RS256",
          consumer = { id = consumer.id },
          key = "a3fc3049b36249a8c9f8891cb127243c###00",
          rsa_public_key = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtFxJlztp0SOk2W40t01f\nxXOzrTu/6v3cBjpnhdzDVSoSPCOyNWF7iSZQTO8qYtNWmYUQAQMYHeE++Yz4ut0A\n1BhkthOoSh0NUt+M63LUYO+9M2Uz5dZ9X3Dkz5m1JVEspRF11JEqnLMMvQ+KRozK\nhyb31M+HOqQQHfltucD7IRolUKaVA8hZ964t12LdgVaxh5Od1qa2Gbt+7nrv9bIn\nHOXsZAZiTF1JrZjb5xzRl5/zhno9iPG4FIjsehWPqNedPhUXrcfa/a90ev1wyj3G\naqRwjYvv2jGJV5FRmbdLfNzQWyO9QtEg8gxwZavJl81G+V2hEhivJdewp0e223c3\nwwIDAQAB\n-----END PUBLIC KEY-----",
        }
        bp.jwt_secrets:insert {
          algorithm = "RS256",
          consumer = { id = consumer.id },
          key = "a3fc3049b36249a8c9f8891cb127243c###01",
          rsa_public_key = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApd4fych/9lISFWGE2TEL\nWte450MJDgxJYaQ0Gs3ZpDxumIR0NTN0RF+m970etTV7NSmxjjzqjgznfFOir4h8\nsTBu1j01fVCC9gi6q9W1yLPSKOc4xG260MHp7SjAuCVBxD40GqBi5giD6uKMGKBu\n/LgeqVjun9JHBtipYnsjtxIIgOMomWzw2vuBPHJnmnVNwylbLS1m8r1jWqFb3AFU\nFsJS84a/Rz8c/Rc+b1b6AbCqcV2tj4FZ+3+PqdiZJ3HDrslSaG8wfmAp6t/hyPq4\niB7wPJDlMtLJf0vJeG6KuMO8hRqrVN3CrL9zFKrP2PI7oXN4r9dDuvOqLm4GgdEI\nAwIDAQAB\n-----END PUBLIC KEY-----",
        }
        bp.jwt_secrets:insert {
          algorithm = "RS256",
          consumer = { id = consumer.id },
          key = "a3fc3049b36249a8c9f8891cb127243c###02",
          rsa_public_key = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAhhBBH6wM5022oIvaTVq6\nQUlwutyKwCebwA+yuT/G1qTzIkta7uJuSP4zg+BHKXe+eE6nA9FuxVdt/albJRRY\nvZthg/cqIIa9B2biHzuparXz+wpUHISG69ylMkV2EMODiiuXSR7ujHXe/ZrLsPFF\n14RxD/uYfAwlurSqkbvzmK4A4Zg1syyZ82j3ftqCufQtyg5sQcA12yEmq3MsnsOw\n6tGUSRhjDm43ohMGEg3eDcbkLFepdHMHVlTcNGp/u1Sk0HEcgbwLSJvbGsYYtxKQ\n/2vkMbKhnBkt6qZPUYsYc1aVMVLXQ1OlkyPHYW9+GIH5rlza5HHmGkIYB+V0dozX\n9wIDAQAB\n-----END PUBLIC KEY-----",
        }
        -- start kong
        assert(helpers.start_kong({
          -- set the strategy
          database = strategy,
          -- use the custom test template to create a local mock server
          nginx_conf = "spec/fixtures/custom_nginx.template",
          -- make sure our plugin gets loaded
          plugins = "bundled," .. PLUGIN_NAME,
          -- write & load declarative config, only if 'strategy = off'
          declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong(nil, true)
      end)

      -- before_each: runs before each child test
      before_each(function()
        client = helpers.proxy_client()
      end)

      -- after_each: runs after each child test
      after_each(function()
        if client then client:close() end
      end)

      describe(PLUGIN_NAME .. ": (generic)", function()
        it("missing 'Authorization' in request header", function()
          local r = client:get("/", {
            headers = {
              host = "ejwt.kong.com"
            }
          })
          assert.response(r).has.status(401)
          local reponse_body = assert.response(r).kong_response._cached_body
          assert.equal("{\"message\":\"Unauthorized\"}", reponse_body)
        end)

        it("invalid 'Authorization' in request header", function()
          local r = client:get("/", {
            headers = {
              host = "ejwt.kong.com",
              authorization = "Aearer 1234567890"
            }
          })
          assert.response(r).has.status(401)
          local reponse_body = assert.response(r).kong_response._cached_body
          assert.equal("{\"message\":\"Unauthorized\"}", reponse_body)
        end)

        it("bad jsonified 'Authorization' in request header", function()
          local r = client:get("/", {
            headers = {
              host = "ejwt.kong.com",
              authorization = "Bearer 1234567890"
            }
          })
          assert.response(r).has.status(401)
          local reponse_body = assert.response(r).kong_response._cached_body
          assert.equal("{\"message\":\"Bad token; invalid JSON\"}", reponse_body)
        end)

        it("no credentials available in jwt_secrets", function()
          local r = client:get("/", {
            headers = {
              host = "ejwt.kong.com",
              -- iss: a36c3039b36249a3c9f88910b127243c
              authorization = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhMzZjMzAzOWIzNjI0OWEzYzlmODg5MTBiMTI3MjQzYyIsImV4cCI6MjAwMjQzMDA1NCwibmJmIjoyMDAyNDMwMDU0LCJpYXQiOjE3MzIwNzY3Mzl9.HyJ0EsZiZUim-B_BeZJGpg365WrbSCPU8Dyl_iiU45g9Dnru4wJiWVqrfCEol658AEQzpZCDJlrLfBPyRrhu5ung6wnz97x-f20Om9djNWhA9moIyoFCMi-X80ibklDT9U6HFjzGuFocaCbc6hzKhie44kU_biOLax7h7eiSyUHUXrZdtKwR5Wi9Flec8MTuToKfwZD4rA3L1ie7lsYYmVewauprbaLql_DAXL7CF-mbNwTOHu0J8vxnOulaLyXr1W-7y2qAjMdHsMdVyqgxOPag-4Pn0D5yha4SoqNJvgzW3t9Bnx63aE1VqH_sCnWkMPlbmrkta0sQVQw3JguQFg"
            }
          })
          assert.response(r).has.status(401)
          local reponse_body = assert.response(r).kong_response._cached_body
          assert.equal("{\"message\":\"No credentials available for given 'iss'\"}", reponse_body)
        end)

        it("successful verified jwt token via plugin", function()
          local r = client:get("/", {
            headers = {
              host = "ejwt.kong.com",
              authorization = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhM2ZjMzA0OWIzNjI0OWE4YzlmODg5MWNiMTI3MjQzYyIsImV4cCI6MjAwMjQzMDA1NCwibmJmIjoyMDAyNDMwMDU0LCJpYXQiOjE3MzIwNzY3Mzl9.qR9Zh0yseTEva4A3bi_USPsmqKtkXgJkwN5szHYD4H7U4ewbimUtasUQoU6SDRNwyHjPeljXvqTRUtUuuG9bEFrroilNjkan5Gq5FTX7TUf2kmR9by4gkwpIoJu8In8R3_reUt2gk7XYQbzqo-mDhfyDWks36vlLahwXwDvOq4UNZvwOOQQNCkertiOXQDc_Wxc7I5NvQW1Sdt5483IkAHuBq-W9I4En2VA3hXINuDzxjGnOR7-2AmhDo5-9VyhYB-Osk14lYU5H74vt-2mLSvEey_tOl624haIFT2hPFXBjL8O5lSn_RWrPN-bbIDlkIbei0hmBoZJDxbmPsTwM2Q"
            }
          })
          assert.response(r).has.status(200)
          local reponse_body = assert.response(r).kong_response._cached_body
          local respose_json = cjson.decode(reponse_body)
          local header_token = respose_json["headers"]["authorization"]
          assert.is_true(string.sub(header_token, 1, #"Bearer ") == "Bearer ")
        end)
      end)
    end)
  end
end
