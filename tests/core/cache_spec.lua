local cache = require("dbab.core.cache")
local schema = require("dbab.core.schema")
local connection = require("dbab.core.connection")

describe("cache", function()
  local original_get_active_url
  local original_get_cached_table_names
  local original_get_cached_columns
  local original_get_schemas_async
  local original_get_tables_async

  before_each(function()
    original_get_active_url = connection.get_active_url
    original_get_cached_table_names = schema.get_cached_table_names
    original_get_cached_columns = schema.get_cached_columns
    original_get_schemas_async = schema.get_schemas_async
    original_get_tables_async = schema.get_tables_async
    cache.is_loading_flag = false
  end)

  after_each(function()
    connection.get_active_url = original_get_active_url
    schema.get_cached_table_names = original_get_cached_table_names
    schema.get_cached_columns = original_get_cached_columns
    schema.get_schemas_async = original_get_schemas_async
    schema.get_tables_async = original_get_tables_async
    cache.is_loading_flag = false
  end)

  it("returns cached tables for explicit URL", function()
    schema.get_cached_table_names = function(url)
      if url == "postgres://db/a" then
        return { "users" }
      end
      return { "orders" }
    end

    local tables_a = cache.get_table_names_cached("postgres://db/a")
    local tables_b = cache.get_table_names_cached("postgres://db/b")

    assert.are.same({ "users" }, tables_a)
    assert.are.same({ "orders" }, tables_b)
  end)

  it("returns cached columns for explicit URL", function()
    schema.get_cached_columns = function(url)
      if url == "postgres://db/a" then
        return { { name = "id", data_type = "int", is_primary = true } }
      end
      return { { name = "order_id", data_type = "int", is_primary = false } }
    end

    local cols_a = cache.get_all_columns_cached("postgres://db/a")
    local cols_b = cache.get_all_columns_cached("postgres://db/b")

    assert.are.same({ { name = "id", data_type = "int", is_primary = true } }, cols_a)
    assert.are.same({ { name = "order_id", data_type = "int", is_primary = false } }, cols_b)
  end)

  it("uses explicit URL for warmup instead of active connection", function()
    local requested = {}

    connection.get_active_url = function()
      return "postgres://active/should-not-be-used"
    end

    schema.get_schemas_async = function(url, callback)
      table.insert(requested, { step = "schemas", url = url })
      callback({ { name = "public" } }, nil)
    end

    schema.get_tables_async = function(url, schema_name, callback)
      table.insert(requested, { step = "tables", url = url, schema_name = schema_name })
      callback({}, nil)
    end

    cache.warmup(nil, "postgres://explicit/context")

    assert.are.same("schemas", requested[1].step)
    assert.are.same("postgres://explicit/context", requested[1].url)
    assert.are.same("tables", requested[2].step)
    assert.are.same("postgres://explicit/context", requested[2].url)
    assert.are.same("public", requested[2].schema_name)
    assert.is_false(cache.is_loading())
  end)
end)
