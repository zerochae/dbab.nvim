local connection = require("dbab.core.connection")
local config = require("dbab.config")

describe("connection", function()
  -- Setup test connections
  before_each(function()
    config.setup({
      connections = {
        { name = "test_pg", url = "postgres://localhost/testdb" },
        { name = "test_mysql", url = "mysql://localhost/testdb" },
        { name = "test_sqlite", url = "sqlite:///tmp/test.db" },
        { name = "env_conn", url = "$TEST_DB_URL" },
      },
    })
    connection.active_url = nil
    connection.active_name = nil
  end)

  describe("parse_type", function()
    it("detects postgres from postgres:// URL", function()
      assert.are.equal("postgres", connection.parse_type("postgres://localhost/db"))
    end)

    it("detects postgres from postgresql:// URL", function()
      assert.are.equal("postgres", connection.parse_type("postgresql://localhost/db"))
    end)

    it("detects mysql", function()
      assert.are.equal("mysql", connection.parse_type("mysql://localhost/db"))
    end)

    it("detects mariadb as mysql", function()
      assert.are.equal("mysql", connection.parse_type("mariadb://localhost/db"))
    end)

    it("detects sqlite", function()
      assert.are.equal("sqlite", connection.parse_type("sqlite:///path/to/db"))
    end)

    it("returns unknown for unrecognized URL", function()
      assert.are.equal("unknown", connection.parse_type("mongodb://localhost/db"))
    end)
  end)

  describe("resolve_url", function()
    it("returns URL as-is if not environment variable", function()
      local url = "postgres://localhost/db"
      assert.are.equal(url, connection.resolve_url(url))
    end)

    it("expands environment variable", function()
      -- Set test env var
      vim.fn.setenv("TEST_RESOLVE_URL", "postgres://resolved/db")

      local resolved = connection.resolve_url("$TEST_RESOLVE_URL")
      assert.are.equal("postgres://resolved/db", resolved)

      -- Cleanup
      vim.fn.setenv("TEST_RESOLVE_URL", nil)
    end)

    it("returns original if env var not found", function()
      local url = "$NON_EXISTENT_VAR_12345"
      assert.are.equal(url, connection.resolve_url(url))
    end)
  end)

  describe("get_connection_by_name", function()
    it("returns connection when found", function()
      local conn = connection.get_connection_by_name("test_pg")
      assert.is_not_nil(conn)
      assert.are.equal("test_pg", conn.name)
      assert.are.equal("postgres://localhost/testdb", conn.url)
    end)

    it("returns nil when not found", function()
      local conn = connection.get_connection_by_name("non_existent")
      assert.is_nil(conn)
    end)
  end)

  describe("set_active", function()
    it("sets active connection when found", function()
      local result = connection.set_active("test_pg")
      assert.is_true(result)
      assert.are.equal("test_pg", connection.get_active_name())
      assert.are.equal("postgres://localhost/testdb", connection.get_active_url())
    end)

    it("returns false when connection not found", function()
      local result = connection.set_active("non_existent")
      assert.is_false(result)
      assert.is_nil(connection.get_active_name())
    end)

    it("resolves environment variable URLs", function()
      vim.fn.setenv("TEST_DB_URL", "postgres://env/db")

      local result = connection.set_active("env_conn")
      assert.is_true(result)
      assert.are.equal("postgres://env/db", connection.get_active_url())

      vim.fn.setenv("TEST_DB_URL", nil)
    end)
  end)

  describe("get_active_url and get_active_name", function()
    it("returns nil when no connection is active", function()
      assert.is_nil(connection.get_active_url())
      assert.is_nil(connection.get_active_name())
    end)

    it("returns values after setting active", function()
      connection.set_active("test_mysql")
      assert.are.equal("mysql://localhost/testdb", connection.get_active_url())
      assert.are.equal("test_mysql", connection.get_active_name())
    end)
  end)

  describe("list_connections", function()
    it("returns all configured connections", function()
      local connections = connection.list_connections()
      assert.are.equal(4, #connections)
    end)

    it("returns empty list when no connections configured", function()
      config.setup({ connections = {} })
      local connections = connection.list_connections()
      assert.are.equal(0, #connections)
    end)
  end)
end)
