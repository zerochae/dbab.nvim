local cache = require("dbab.core.cache")
local connection = require("dbab.core.connection")

local source = {}

---@return string|nil
local function get_context_url()
  local ok, workbench = pcall(require, "dbab.ui.workbench")
  if ok and workbench and workbench.get_active_connection_context then
    local _, tab_url = workbench.get_active_connection_context()
    if tab_url then
      return tab_url
    end
  end
  return connection.get_active_url()
end

local kinds
local keyword_items

local function get_kinds()
  if not kinds then
    kinds = require("blink.cmp.types").CompletionItemKind
  end
  return kinds
end

local function get_keyword_items()
  if not keyword_items then
    local k = get_kinds()
    local keywords = {
      "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
      "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "OFFSET", "JOIN", "LEFT JOIN",
      "RIGHT JOIN", "INNER JOIN", "OUTER JOIN", "ON", "AS", "DISTINCT", "COUNT",
      "SUM", "AVG", "MIN", "MAX", "INSERT INTO", "VALUES", "UPDATE", "SET",
      "DELETE FROM", "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "NULL",
      "IS NULL", "IS NOT NULL", "ASC", "DESC", "CASE", "WHEN", "THEN", "ELSE", "END",
      "UNION", "ALL", "EXISTS", "CAST", "COALESCE", "NULLIF",
      "PRIMARY KEY", "FOREIGN KEY", "REFERENCES", "UNIQUE", "INDEX",
      "CREATE DATABASE", "DROP DATABASE", "USE", "SHOW TABLES", "DESCRIBE",
      "CREATE INDEX", "DROP INDEX", "TRUNCATE", "BEGIN", "COMMIT", "ROLLBACK",
    }
    keyword_items = {}
    for _, kw in ipairs(keywords) do
      table.insert(keyword_items, {
        label = kw,
        kind = k.Keyword,
        sortText = "2" .. kw,
      })
    end
  end
  return keyword_items
end

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  local ft = vim.bo.filetype
  return (ft == "sql" or ft == "dbab_editor") and get_context_url() ~= nil
end

function source:get_trigger_characters()
  return { ".", " " }
end

function source:get_debug_name()
  return "dbab"
end

function source:get_completions(_, callback)
  local k = get_kinds()
  local items = {}
  local seen = {}

  for _, item in ipairs(get_keyword_items()) do
    table.insert(items, vim.deepcopy(item))
  end

  local context_url = get_context_url()
  local tables = cache.get_table_names_cached(context_url)
  for _, tbl in ipairs(tables) do
    if not seen[tbl] then
      seen[tbl] = true
      table.insert(items, {
        label = tbl,
        kind = k.Class,
        detail = "Table",
        sortText = "0" .. tbl,
      })
    end
  end

  local columns = cache.get_all_columns_cached(context_url)
  for _, col in ipairs(columns) do
    if not seen[col.name] then
      seen[col.name] = true
      local detail = col.data_type or "Column"
      if col.is_primary then
        detail = detail .. " (PK)"
      end
      table.insert(items, {
        label = col.name,
        kind = k.Field,
        detail = detail,
        sortText = "1" .. col.name,
      })
    end
  end

  callback({
    items = items,
    is_incomplete_forward = cache.is_loading(),
    is_incomplete_backward = false,
  })
end

return source
