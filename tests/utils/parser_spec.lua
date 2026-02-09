local parser = require("dbab.utils.parser")

describe("parser", function()
  describe("parse", function()
    it("parses empty input", function()
      local result = parser.parse("")
      -- Empty string results in single "result" column with no rows
      assert.are.equal(1, #result.columns)
      assert.are.equal("result", result.columns[1])
      assert.are.equal(0, #result.rows)
      assert.are.equal(0, result.row_count)
    end)

    it("parses PostgreSQL format with rows", function()
      local raw = [[
 id | name  | email
----+-------+------------------
  1 | Alice | alice@example.com
  2 | Bob   | bob@example.com
(2 rows)]]

      local result = parser.parse(raw)

      assert.are.equal(3, #result.columns)
      assert.are.equal("id", result.columns[1])
      assert.are.equal("name", result.columns[2])
      assert.are.equal("email", result.columns[3])

      assert.are.equal(2, #result.rows)
      assert.are.equal("1", result.rows[1][1])
      assert.are.equal("Alice", result.rows[1][2])
      assert.are.equal("alice@example.com", result.rows[1][3])

      assert.are.equal(2, result.row_count)
    end)

    it("parses single row result", function()
      local raw = [[
 count
-------
    42
(1 row)]]

      local result = parser.parse(raw)

      assert.are.equal(1, #result.columns)
      assert.are.equal("count", result.columns[1])
      assert.are.equal(1, #result.rows)
      assert.are.equal("42", result.rows[1][1])
      assert.are.equal(1, result.row_count)
    end)

    it("handles empty result set", function()
      local raw = [[
 id | name
----+------
(0 rows)]]

      local result = parser.parse(raw)

      assert.are.equal(2, #result.columns)
      assert.are.equal(0, #result.rows)
      assert.are.equal(0, result.row_count)
    end)

    it("handles NULL values as empty strings", function()
      local raw = [[
 id | value
----+-------
  1 |
  2 | test
(2 rows)]]

      local result = parser.parse(raw)

      assert.are.equal(2, #result.rows)
      assert.are.equal("", result.rows[1][2])
      assert.are.equal("test", result.rows[2][2])
    end)

    it("preserves raw output", function()
      local raw = "some raw output"
      local result = parser.parse(raw)
      assert.are.equal(raw, result.raw)
    end)

    it("handles text without separator as single column", function()
      local raw = [[line1
line2
line3]]

      local result = parser.parse(raw)

      assert.are.equal(1, #result.columns)
      assert.are.equal("result", result.columns[1])
      assert.are.equal(3, #result.rows)
    end)

    it("ignores mysql password warning", function()
      local raw = [[mysql: [Warning] Using a password on the command line interface can be insecure.
 id | name
----+------
  1 | test
(1 row)]]

      local result = parser.parse(raw)

      assert.are.equal(2, #result.columns)
      assert.are.equal("id", result.columns[1])
      assert.are.equal(1, #result.rows)
      assert.are.equal("test", result.rows[1][2])
    end)

    it("handles raw style", function()
      local raw = "line1\nline2"
      local result = parser.parse(raw, "raw")

      assert.are.equal(1, #result.columns)
      assert.are.equal("raw", result.columns[1])
      assert.are.equal(2, #result.rows)
      assert.are.equal("line1", result.rows[1][1])
      assert.are.equal(raw, result.raw)
    end)

    it("handles json style", function()
      local raw = [[
 id | name
----+-------
  1 | Alice
  2 | Bob
(2 rows)]]

      local result = parser.parse(raw, "json")

      assert.are.equal(2, result.row_count)
      -- Check if raw contains valid JSON structure
      assert.is_true(result.raw:find('%[') ~= nil)
      assert.is_true(result.raw:find('Alice') ~= nil)
      assert.is_true(result.raw:find('"id"') ~= nil)
    end)

    it("handles vertical style", function()
      local raw = [[
 id | name
----+-------
  1 | Alice
  2 | Bob
(2 rows)]]

      local result = parser.parse(raw, "vertical")

      assert.are.equal(2, result.row_count)
      assert.are.equal(2, #result.columns)
      assert.is_true(result.raw:find("RECORD 1") ~= nil)
      assert.is_true(result.raw:find("RECORD 2") ~= nil)
      assert.is_true(result.raw:find("Alice") ~= nil)
      -- rows는 string[][] 형태
      assert.is_true(type(result.rows[1]) == "table")
    end)

    it("handles vertical style with empty result", function()
      local raw = [[
 id | name
----+------
(0 rows)]]

      local result = parser.parse(raw, "vertical")

      assert.are.equal(0, result.row_count)
      assert.are.equal(0, #result.rows)
    end)

    it("handles markdown style", function()
      local raw = [[
 id | name
----+-------
  1 | Alice
  2 | Bob
(2 rows)]]

      local result = parser.parse(raw, "markdown")

      assert.are.equal(2, result.row_count)
      assert.are.equal(2, #result.columns)
      -- Markdown 테이블 형식 확인
      assert.is_true(result.raw:find("^|") ~= nil)
      assert.is_true(result.raw:find("%-%-") ~= nil)
      assert.is_true(result.raw:find("Alice") ~= nil)
      -- Header + separator + 2 data rows = 4 lines
      assert.are.equal(4, #result.rows)
    end)

    it("handles markdown style with empty result", function()
      local raw = [[
 id | name
----+------
(0 rows)]]

      local result = parser.parse(raw, "markdown")

      assert.are.equal(0, result.row_count)
      -- Header + separator만 존재
      assert.are.equal(2, #result.rows)
    end)
  end)

  describe("calculate_column_widths", function()
    it("returns widths based on header", function()
      local result = {
        columns = { "id", "name" },
        rows = {},
      }

      local widths = parser.calculate_column_widths(result)

      assert.are.equal(2, widths[1]) -- "id" = 2
      assert.are.equal(4, widths[2]) -- "name" = 4
    end)

    it("considers data cell widths", function()
      local result = {
        columns = { "id", "name" },
        rows = {
          { "1", "Alice" },
          { "123", "Bob" },
        },
      }

      local widths = parser.calculate_column_widths(result)

      assert.are.equal(3, widths[1]) -- max("id"=2, "1"=1, "123"=3) = 3
      assert.are.equal(5, widths[2]) -- max("name"=4, "Alice"=5, "Bob"=3) = 5
    end)

    it("handles empty result", function()
      local result = {
        columns = {},
        rows = {},
      }

      local widths = parser.calculate_column_widths(result)

      assert.are.equal(0, #widths)
    end)
  end)
end)
