local operations = require "kong.db.migrations.operations.200_to_210"


local plugin_entities = {
  {
    name = "ejwt_secrets",
    primary_key = "nid",
    uniques = {"nid"},
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}

return operations.ws_migrate_plugin(plugin_entities)
