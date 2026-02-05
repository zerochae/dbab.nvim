-- CMP source for dbab
-- Uses cached schema data (no blocking DB queries)

local cache = require("dbab.core.cache")
local connection = require("dbab.core.connection")

local source = {}

source.new = function()
  return setmetatable({}, { __index = source })
end

source.get_keyword_pattern = function()
  return [[\w\+]]
end

source.get_trigger_characters = function()
  return { ".", " " }
end

source.is_available = function()
  local ft = vim.bo.filetype
  return (ft == "sql" or ft == "dbab_editor") and connection.get_active_url() ~= nil
end

source.get_debug_name = function()
  return "dbab"
end

-- SQL keywords (static)
local keywords = {
  "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
  "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "OFFSET", "JOIN", "LEFT JOIN",
  "RIGHT JOIN", "INNER JOIN", "OUTER JOIN", "ON", "AS", "DISTINCT", "COUNT",
  "SUM", "AVG", "MIN", "MAX", "INSERT INTO", "VALUES", "UPDATE", "SET",
  "DELETE FROM", "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "NULL",
  "IS NULL", "IS NOT NULL", "ASC", "DESC", "CASE", "WHEN", "THEN", "ELSE", "END",
}

-- Pre-built keyword items
local keyword_items = {}
for _, kw in ipairs(keywords) do
  table.insert(keyword_items, {
    label = kw,
    kind = 14, -- Keyword
    detail = "SQL",
    sortText = "2" .. kw,
  })
end

source.complete = function(_, _, callback)
  local items = {}
  local seen = {}

  -- Add SQL keywords
  for _, item in ipairs(keyword_items) do
    table.insert(items, item)
  end

  -- Add cached table names (NO DB queries)
  local tables = cache.get_table_names_cached()
  for _, tbl in ipairs(tables) do
    if not seen[tbl] then
      seen[tbl] = true
      table.insert(items, {
        label = tbl,
        kind = 7, -- Class
        detail = "Table",
        sortText = "0" .. tbl,
      })
    end
  end

  -- Add cached column names (NO DB queries)
  local columns = cache.get_all_columns_cached()
  for _, col in ipairs(columns) do
    if not seen[col.name] then
      seen[col.name] = true
      local detail = col.data_type or "Column"
      if col.is_primary then
        detail = detail .. " (PK)"
      end
      table.insert(items, {
        label = col.name,
        kind = 5, -- Field
        detail = detail,
        sortText = "1" .. col.name,
      })
    end
  end

  callback({
    items = items,
    isIncomplete = cache.is_loading(),
  })
end

return source
