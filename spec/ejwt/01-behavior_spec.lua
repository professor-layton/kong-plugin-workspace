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
        local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })
        local route = bp.routes:insert({
          hosts = { "ejwt.kong.com" },
        })
        -- add the plugin to test the route previously created
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = route.id },
          config = {
            max_multi_rsa = 5
          },
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
      end)
    end)
  end
end
