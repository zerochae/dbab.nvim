local storage = require("dbab.core.storage")

describe("storage", function()
  local test_conn = "test_connection"
  local test_query_name = "test_query"
  local test_content = "SELECT * FROM users WHERE id = 1;"

  -- Clean up before and after tests
  local function cleanup()
    pcall(storage.delete_query, test_conn, test_query_name)
    pcall(storage.delete_query, test_conn, "renamed_query")
    pcall(storage.delete_query, test_conn, "query1")
    pcall(storage.delete_query, test_conn, "query2")
    -- Remove test directory if empty
    local dir = storage.get_connection_dir(test_conn)
    pcall(vim.fn.delete, dir, "d")
  end

  before_each(function()
    cleanup()
  end)

  after_each(function()
    cleanup()
  end)

  describe("get_queries_dir", function()
    it("returns path under stdpath data", function()
      local dir = storage.get_queries_dir()
      assert.is_not_nil(dir)
      assert.is_true(dir:match("dbab/queries$") ~= nil)
    end)
  end)

  describe("get_connection_dir", function()
    it("returns path with connection name", function()
      local dir = storage.get_connection_dir("my_db")
      assert.is_true(dir:match("my_db$") ~= nil)
    end)
  end)

  describe("get_query_path", function()
    it("returns path with .sql extension", function()
      local path = storage.get_query_path("conn", "query")
      assert.is_true(path:match("query%.sql$") ~= nil)
    end)

    it("does not double .sql extension", function()
      local path = storage.get_query_path("conn", "query.sql")
      assert.is_true(path:match("query%.sql$") ~= nil)
      assert.is_nil(path:match("%.sql%.sql"))
    end)

    it("sanitizes invalid characters", function()
      local path = storage.get_query_path("conn", "my/bad:query")
      assert.is_nil(path:match("/bad:"))
      assert.is_true(path:match("my_bad_query%.sql$") ~= nil)
    end)
  end)

  describe("save_query and load_query", function()
    it("saves and loads query content", function()
      local ok, err = storage.save_query(test_conn, test_query_name, test_content)
      assert.is_true(ok)
      assert.is_nil(err)

      local content, load_err = storage.load_query(test_conn, test_query_name)
      assert.is_nil(load_err)
      assert.are.equal(test_content, content)
    end)

    it("creates directory if not exists", function()
      local ok, _ = storage.save_query(test_conn, test_query_name, test_content)
      assert.is_true(ok)

      local dir = storage.get_connection_dir(test_conn)
      assert.are.equal(1, vim.fn.isdirectory(dir))
    end)

    it("overwrites existing query", function()
      storage.save_query(test_conn, test_query_name, "old content")
      storage.save_query(test_conn, test_query_name, "new content")

      local content, _ = storage.load_query(test_conn, test_query_name)
      assert.are.equal("new content", content)
    end)
  end)

  describe("list_queries", function()
    it("returns empty list for non-existent connection", function()
      local queries = storage.list_queries("non_existent_conn")
      assert.are.equal(0, #queries)
    end)

    it("lists saved queries", function()
      storage.save_query(test_conn, "query1", "SELECT 1")
      storage.save_query(test_conn, "query2", "SELECT 2")

      local queries = storage.list_queries(test_conn)
      assert.are.equal(2, #queries)

      local names = {}
      for _, q in ipairs(queries) do
        names[q.name] = true
      end
      assert.is_true(names["query1"])
      assert.is_true(names["query2"])
    end)

    it("includes path and modified time", function()
      storage.save_query(test_conn, test_query_name, test_content)

      local queries = storage.list_queries(test_conn)
      assert.are.equal(1, #queries)
      assert.is_not_nil(queries[1].path)
      assert.is_not_nil(queries[1].modified)
      assert.is_true(queries[1].modified > 0)
    end)
  end)

  describe("delete_query", function()
    it("deletes existing query", function()
      storage.save_query(test_conn, test_query_name, test_content)
      assert.is_true(storage.query_exists(test_conn, test_query_name))

      local ok, err = storage.delete_query(test_conn, test_query_name)
      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_false(storage.query_exists(test_conn, test_query_name))
    end)

    it("returns error for non-existent query", function()
      local ok, err = storage.delete_query(test_conn, "non_existent")
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)

  describe("rename_query", function()
    it("renames existing query", function()
      storage.save_query(test_conn, test_query_name, test_content)

      local ok, err = storage.rename_query(test_conn, test_query_name, "renamed_query")
      assert.is_true(ok)
      assert.is_nil(err)

      assert.is_false(storage.query_exists(test_conn, test_query_name))
      assert.is_true(storage.query_exists(test_conn, "renamed_query"))

      local content, _ = storage.load_query(test_conn, "renamed_query")
      assert.are.equal(test_content, content)
    end)

    it("returns error if source does not exist", function()
      local ok, err = storage.rename_query(test_conn, "non_existent", "new_name")
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)

    it("returns error if target already exists", function()
      storage.save_query(test_conn, "query1", "content 1")
      storage.save_query(test_conn, "query2", "content 2")

      local ok, err = storage.rename_query(test_conn, "query1", "query2")
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)

  describe("query_exists", function()
    it("returns true for existing query", function()
      storage.save_query(test_conn, test_query_name, test_content)
      assert.is_true(storage.query_exists(test_conn, test_query_name))
    end)

    it("returns false for non-existent query", function()
      assert.is_false(storage.query_exists(test_conn, "non_existent"))
    end)
  end)

  describe("get_query_count", function()
    it("returns 0 for empty connection", function()
      assert.are.equal(0, storage.get_query_count("empty_conn"))
    end)

    it("returns correct count", function()
      storage.save_query(test_conn, "query1", "SELECT 1")
      storage.save_query(test_conn, "query2", "SELECT 2")

      assert.are.equal(2, storage.get_query_count(test_conn))
    end)
  end)
end)
