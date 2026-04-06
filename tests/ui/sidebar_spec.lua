local connection = require("dbab.core.connection")

describe("sidebar", function()
  describe("table quote style", function()
    local function build_select_query(url, table_name, schema)
      local db_type = url and connection.parse_type(url) or "unknown"
      local q = db_type == "mysql" and "`" or '"'
      local schema_prefix = schema and schema ~= "public" and (q .. schema .. q .. ".") or ""
      return string.format("SELECT * FROM %s%s%s%s LIMIT 10;", schema_prefix, q, table_name, q)
    end

    it("uses backticks for mysql", function()
      local query = build_select_query("mysql://localhost/testdb", "users", nil)
      assert.are.equal("SELECT * FROM `users` LIMIT 10;", query)
    end)

    it("uses backticks for mariadb", function()
      local query = build_select_query("mariadb://localhost/testdb", "orders", nil)
      assert.are.equal("SELECT * FROM `orders` LIMIT 10;", query)
    end)

    it("uses double quotes for postgres", function()
      local query = build_select_query("postgres://localhost/testdb", "users", nil)
      assert.are.equal('SELECT * FROM "users" LIMIT 10;', query)
    end)

    it("uses double quotes for postgresql", function()
      local query = build_select_query("postgresql://localhost/testdb", "users", nil)
      assert.are.equal('SELECT * FROM "users" LIMIT 10;', query)
    end)

    it("uses double quotes for sqlite", function()
      local query = build_select_query("sqlite:///tmp/test.db", "logs", nil)
      assert.are.equal('SELECT * FROM "logs" LIMIT 10;', query)
    end)

    it("uses double quotes for unknown db type", function()
      local query = build_select_query(nil, "data", nil)
      assert.are.equal('SELECT * FROM "data" LIMIT 10;', query)
    end)

    it("includes schema prefix for mysql", function()
      local query = build_select_query("mysql://localhost/testdb", "users", "myschema")
      assert.are.equal("SELECT * FROM `myschema`.`users` LIMIT 10;", query)
    end)

    it("includes schema prefix for postgres non-public", function()
      local query = build_select_query("postgres://localhost/testdb", "users", "custom")
      assert.are.equal('SELECT * FROM "custom"."users" LIMIT 10;', query)
    end)

    it("omits schema prefix for postgres public", function()
      local query = build_select_query("postgres://localhost/testdb", "users", "public")
      assert.are.equal('SELECT * FROM "users" LIMIT 10;', query)
    end)

    it("handles table names with special characters in mysql", function()
      local query = build_select_query("mysql://localhost/testdb", "my-table", nil)
      assert.are.equal("SELECT * FROM `my-table` LIMIT 10;", query)
    end)

    it("handles table names with spaces in mysql", function()
      local query = build_select_query("mysql://localhost/testdb", "my table", nil)
      assert.are.equal("SELECT * FROM `my table` LIMIT 10;", query)
    end)
  end)
end)
