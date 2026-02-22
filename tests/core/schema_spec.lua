local schema = require("dbab.core.schema")
local executor = require("dbab.core.executor")
local config = require("dbab.config")

describe("schema cache", function()
  before_each(function()
    config.setup({
      connections = {},
      sidebar = { show_system_schemas = true },
    })
    schema.clear_cache()
  end)

  after_each(function()
    schema.clear_cache()
  end)

  it("keeps schema cache per URL", function()
    local url_a = "sqlite:///tmp/db_a.sqlite"
    local url_b = "sqlite:///tmp/db_b.sqlite"

    schema.get_schemas(url_a)
    schema.get_schemas(url_b)

    assert.is_true(schema.has_cache(url_a))
    assert.is_true(schema.has_cache(url_b))

    schema.clear_cache(url_a)

    assert.is_false(schema.has_cache(url_a))
    assert.is_true(schema.has_cache(url_b))
  end)

  it("keeps table cache isolated per URL", function()
    local original_execute = executor.execute

    executor.execute = function(url)
      if url:find("db_a") then
        return "table_name\ttable_type\nusers\tBASE TABLE"
      end
      return "table_name\ttable_type\norders\tBASE TABLE"
    end

    local ok, err = pcall(function()
      local url_a = "sqlite:///tmp/db_a.sqlite"
      local url_b = "sqlite:///tmp/db_b.sqlite"

      schema.get_tables(url_a, "main")
      schema.get_tables(url_b, "main")

      local names_a = schema.get_cached_table_names(url_a)
      local names_b = schema.get_cached_table_names(url_b)

      assert.are.same({ "users" }, names_a)
      assert.are.same({ "orders" }, names_b)
    end)

    executor.execute = original_execute

    if not ok then
      error(err)
    end
  end)
end)
