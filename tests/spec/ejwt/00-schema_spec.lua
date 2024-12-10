local PLUGIN_NAME = "ejwt"

-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("plugins." .. PLUGIN_NAME .. ".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end

describe(PLUGIN_NAME .. ": (schema)", function()
  it("config-schema test: mandatory parameters", function()
    local ok, err = validate({
      max_multi_rsa = 5,
      key_suffix_format = "mock-suffix-format"
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
end)
