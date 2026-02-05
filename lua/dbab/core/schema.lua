local executor = require("dbab.core.executor")
local connection = require("dbab.core.connection")
local config = require("dbab.config")

local M = {}

-- In-memory cache for schema data
local cache = {
  url = nil,
  schemas = nil,
  tables = {}, -- schema_name -> tables
  columns = {}, -- table_name -> columns
}

--- Clear cache (call when connection changes)
function M.clear_cache()
  cache.url = nil
  cache.schemas = nil
  cache.tables = {}
  cache.columns = {}
end

--- Check if cache is valid for current URL
local function is_cache_valid(url)
  return cache.url == url
end

--- Get cached table names only (NO DB queries, for CMP)
---@param url string
---@return string[]
function M.get_cached_table_names(url)
  if not is_cache_valid(url) then
    return {}
  end

  local names = {}
  local seen = {}
  for _, tables in pairs(cache.tables) do
    for _, tbl in ipairs(tables) do
      if not seen[tbl.name] then
        seen[tbl.name] = true
        table.insert(names, tbl.name)
      end
    end
  end
  return names
end

--- Get cached columns only (NO DB queries, for CMP)
---@param url string
---@return Dbab.Column[]
function M.get_cached_columns(url)
  if not is_cache_valid(url) then
    return {}
  end

  local all = {}
  local seen = {}
  for _, columns in pairs(cache.columns) do
    for _, col in ipairs(columns) do
      if not seen[col.name] then
        seen[col.name] = true
        table.insert(all, col)
      end
    end
  end
  return all
end

--- Check if cache has data
---@param url string
---@return boolean
function M.has_cache(url)
  return is_cache_valid(url) and cache.schemas ~= nil
end

--- See lua/dbab/types.lua for type definitions (Dbab.Schema, Dbab.Table, Dbab.Column)

---@param url string
---@return Dbab.Schema[]
function M.get_schemas(url)
  -- Return cached if valid
  if is_cache_valid(url) and cache.schemas then
    return cache.schemas
  end

  -- URL changed, clear old cache
  if not is_cache_valid(url) then
    M.clear_cache()
    cache.url = url
  end

  local db_type = connection.parse_type(url)
  local opts = config.get()
  local query = ""

  if db_type == "postgres" then
    local exclude_list = "'pg_toast', 'pg_temp_1', 'pg_toast_temp_1'"
    if not opts.schema.show_system_schemas then
      exclude_list = exclude_list .. ", 'information_schema', 'pg_catalog'"
    end
    query = string.format([[
      SELECT schema_name,
             (SELECT COUNT(*) FROM information_schema.tables t WHERE t.table_schema = s.schema_name) as table_count
      FROM information_schema.schemata s
      WHERE schema_name NOT IN (%s)
      ORDER BY
        CASE WHEN schema_name = 'public' THEN 0 ELSE 1 END,
        schema_name
    ]], exclude_list)
  elseif db_type == "mysql" then
    query = [[
      SELECT schema_name,
             (SELECT COUNT(*) FROM information_schema.tables t WHERE t.table_schema = s.schema_name) as table_count
      FROM information_schema.schemata s
      WHERE schema_name = DATABASE()
    ]]
  elseif db_type == "sqlite" then
    -- SQLite doesn't have schemas, return a fake "main" schema
    cache.schemas = { { name = "main", table_count = 0 } }
    return cache.schemas
  else
    return {}
  end

  local result = executor.execute(url, query)
  cache.schemas = M.parse_schemas(result)
  return cache.schemas
end

---@param raw string
---@return Dbab.Schema[]
function M.parse_schemas(raw)
  local schemas = {}
  local lines = vim.split(raw, "\n")

  -- 탭 구분 형식 감지 (MySQL)
  local is_tab_separated = lines[1] and lines[1]:find("\t")

  if is_tab_separated then
    -- MySQL 탭 구분 형식: 첫 줄은 헤더, 나머지는 데이터
    for i = 2, #lines do
      local line = lines[i]
      if line ~= "" then
        local parts = vim.split(line, "\t")
        if #parts >= 2 then
          local name = vim.trim(parts[1])
          local count = tonumber(vim.trim(parts[2])) or 0
          if name ~= "" then
            table.insert(schemas, { name = name, table_count = count })
          end
        end
      end
    end
  else
    -- PostgreSQL 파이프 구분 형식
    local data_start = 1
    for i, line in ipairs(lines) do
      if line:match("^%-") or line:match("^%+") or line:match("^─") then
        data_start = i + 1
        break
      end
    end

    for i = data_start, #lines do
      local line = vim.trim(lines[i])
      if line ~= "" and not line:match("^%(") and not line:match("rows%)") then
        local parts = vim.split(line, "|")
        if #parts >= 2 then
          local name = vim.trim(parts[1])
          local count = tonumber(vim.trim(parts[2])) or 0
          if name ~= "" then
            table.insert(schemas, { name = name, table_count = count })
          end
        end
      end
    end
  end

  return schemas
end

---@param url string
---@param schema_name? string
---@return Dbab.Table[]
function M.get_tables(url, schema_name)
  schema_name = schema_name or "public"

  -- Return cached if valid
  if is_cache_valid(url) and cache.tables[schema_name] then
    return cache.tables[schema_name]
  end

  local db_type = connection.parse_type(url)
  local query = ""

  if db_type == "postgres" then
    query = string.format([[
      SELECT table_name, table_type
      FROM information_schema.tables
      WHERE table_schema = '%s'
      ORDER BY table_type, table_name
    ]], schema_name)
  elseif db_type == "mysql" then
    query = [[
      SELECT table_name, table_type
      FROM information_schema.tables
      WHERE table_schema = DATABASE()
      ORDER BY table_type, table_name
    ]]
  elseif db_type == "sqlite" then
    query = [[
      SELECT name as table_name, type as table_type
      FROM sqlite_master
      WHERE type IN ('table', 'view')
      ORDER BY type, name
    ]]
  else
    return {}
  end

  local result = executor.execute(url, query)
  cache.tables[schema_name] = M.parse_tables(result, db_type)
  return cache.tables[schema_name]
end

---@param raw string
---@param db_type string
---@return Dbab.Table[]
function M.parse_tables(raw, db_type)
  local tables = {}
  local lines = vim.split(raw, "\n")

  -- 탭 구분 형식 감지 (MySQL)
  local is_tab_separated = lines[1] and lines[1]:find("\t")

  if is_tab_separated then
    -- MySQL 탭 구분 형식: 첫 줄은 헤더, 나머지는 데이터
    for i = 2, #lines do
      local line = lines[i]
      if line ~= "" then
        local parts = vim.split(line, "\t")
        if #parts >= 2 then
          local name = vim.trim(parts[1])
          local ttype = vim.trim(parts[2])
          if name ~= "" then
            local table_type = "table"
            if ttype:upper():match("VIEW") then
              table_type = "view"
            end
            table.insert(tables, { name = name, type = table_type })
          end
        end
      end
    end
  else
    -- PostgreSQL 파이프 구분 형식
    local data_start = 1
    for i, line in ipairs(lines) do
      if line:match("^%-") or line:match("^%+") or line:match("^─") then
        data_start = i + 1
        break
      end
    end

    for i = data_start, #lines do
      local line = vim.trim(lines[i])
      if line ~= "" and not line:match("^%(") and not line:match("rows%)") then
        -- Parse table name and type
        local name, ttype
        if db_type == "postgres" then
          -- PostgreSQL format: " table_name | BASE TABLE" or " view_name | VIEW"
          name, ttype = line:match("^%s*([%w_]+)%s*|%s*(.+)%s*$")
        else
          -- Generic format
          local parts = vim.split(line, "|")
          if #parts >= 2 then
            name = vim.trim(parts[1])
            ttype = vim.trim(parts[2])
          end
        end

        if name and name ~= "" then
          local table_type = "table"
          if ttype then
            ttype = ttype:upper()
            if ttype:match("VIEW") then
              table_type = "view"
            end
          end
          table.insert(tables, { name = name, type = table_type })
        end
      end
    end
  end

  return tables
end

---@param url string
---@param table_name string
---@return Dbab.Column[]
function M.get_columns(url, table_name)
  -- Return cached if valid
  if is_cache_valid(url) and cache.columns[table_name] then
    return cache.columns[table_name]
  end

  local db_type = connection.parse_type(url)
  local query = ""

  if db_type == "postgres" then
    query = string.format([[
      SELECT
        c.column_name,
        c.data_type,
        c.is_nullable,
        CASE WHEN pk.column_name IS NOT NULL THEN 'YES' ELSE 'NO' END as is_primary
      FROM information_schema.columns c
      LEFT JOIN (
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = '%s' AND tc.constraint_type = 'PRIMARY KEY'
      ) pk ON c.column_name = pk.column_name
      WHERE c.table_name = '%s' AND c.table_schema = 'public'
      ORDER BY c.ordinal_position
    ]], table_name, table_name)
  elseif db_type == "mysql" then
    query = string.format([[
      SELECT
        column_name,
        data_type,
        is_nullable,
        CASE WHEN column_key = 'PRI' THEN 'YES' ELSE 'NO' END as is_primary
      FROM information_schema.columns
      WHERE table_name = '%s' AND table_schema = DATABASE()
      ORDER BY ordinal_position
    ]], table_name)
  elseif db_type == "sqlite" then
    query = string.format("PRAGMA table_info('%s')", table_name)
  else
    return {}
  end

  local result = executor.execute(url, query)
  cache.columns[table_name] = M.parse_columns(result, db_type)
  return cache.columns[table_name]
end

---@param raw string
---@param db_type string
---@return Dbab.Column[]
function M.parse_columns(raw, db_type)
  local columns = {}
  local lines = vim.split(raw, "\n")

  -- 탭 구분 형식 감지 (MySQL)
  local is_tab_separated = lines[1] and lines[1]:find("\t")

  if is_tab_separated then
    -- MySQL 탭 구분 형식: 첫 줄은 헤더, 나머지는 데이터
    for i = 2, #lines do
      local line = lines[i]
      if line ~= "" then
        local parts = vim.split(line, "\t")
        if #parts >= 4 then
          local col = {
            name = vim.trim(parts[1]),
            data_type = vim.trim(parts[2]),
            is_nullable = vim.trim(parts[3]):upper() == "YES",
            is_primary = vim.trim(parts[4]):upper() == "YES",
          }
          if col.name ~= "" then
            table.insert(columns, col)
          end
        end
      end
    end
  else
    -- PostgreSQL/SQLite 파이프 구분 형식
    local data_start = 1
    for i, line in ipairs(lines) do
      if line:match("^%-") or line:match("^%+") or line:match("^─") then
        data_start = i + 1
        break
      end
    end

    for i = data_start, #lines do
      local line = vim.trim(lines[i])
      if line ~= "" and not line:match("^%(") and not line:match("rows%)") then
        local col = {}

        if db_type == "sqlite" then
          -- SQLite PRAGMA format: cid|name|type|notnull|dflt_value|pk
          local parts = vim.split(line, "|")
          if #parts >= 6 then
            col.name = vim.trim(parts[2])
            col.data_type = vim.trim(parts[3])
            col.is_nullable = vim.trim(parts[4]) == "0"
            col.is_primary = vim.trim(parts[6]) == "1"
          end
        else
          -- PostgreSQL format: name | type | nullable | is_primary
          local parts = vim.split(line, "|")
          if #parts >= 4 then
            col.name = vim.trim(parts[1])
            col.data_type = vim.trim(parts[2])
            col.is_nullable = vim.trim(parts[3]):upper() == "YES"
            col.is_primary = vim.trim(parts[4]):upper() == "YES"
          end
        end

        if col.name and col.name ~= "" then
          table.insert(columns, col)
        end
      end
    end
  end

  return columns
end

-- ============================================
-- Async versions (non-blocking)
-- ============================================

---@param url string
---@param callback fun(schemas: Dbab.Schema[], err: string|nil)
function M.get_schemas_async(url, callback)
  -- Return cached if valid
  if is_cache_valid(url) and cache.schemas then
    vim.schedule(function()
      callback(cache.schemas, nil)
    end)
    return
  end

  -- URL changed, clear old cache
  if not is_cache_valid(url) then
    M.clear_cache()
    cache.url = url
  end

  local db_type = connection.parse_type(url)
  local opts = config.get()
  local query = ""

  if db_type == "postgres" then
    local exclude_list = "'pg_toast', 'pg_temp_1', 'pg_toast_temp_1'"
    if not opts.schema.show_system_schemas then
      exclude_list = exclude_list .. ", 'information_schema', 'pg_catalog'"
    end
    query = string.format([[
      SELECT schema_name,
             (SELECT COUNT(*) FROM information_schema.tables t WHERE t.table_schema = s.schema_name) as table_count
      FROM information_schema.schemata s
      WHERE schema_name NOT IN (%s)
      ORDER BY
        CASE WHEN schema_name = 'public' THEN 0 ELSE 1 END,
        schema_name
    ]], exclude_list)
  elseif db_type == "mysql" then
    query = [[
      SELECT schema_name,
             (SELECT COUNT(*) FROM information_schema.tables t WHERE t.table_schema = s.schema_name) as table_count
      FROM information_schema.schemata s
      WHERE schema_name = DATABASE()
    ]]
  elseif db_type == "sqlite" then
    cache.schemas = { { name = "main", table_count = 0 } }
    vim.schedule(function()
      callback(cache.schemas, nil)
    end)
    return
  else
    vim.schedule(function()
      callback({}, nil)
    end)
    return
  end

  executor.execute_async(url, query, function(result, err)
    if err then
      callback({}, err)
      return
    end
    cache.schemas = M.parse_schemas(result)
    callback(cache.schemas, nil)
  end)
end

---@param url string
---@param schema_name string
---@param callback fun(tables: Dbab.Table[], err: string|nil)
function M.get_tables_async(url, schema_name, callback)
  schema_name = schema_name or "public"

  -- Return cached if valid
  if is_cache_valid(url) and cache.tables[schema_name] then
    vim.schedule(function()
      callback(cache.tables[schema_name], nil)
    end)
    return
  end

  local db_type = connection.parse_type(url)
  local query = ""

  if db_type == "postgres" then
    query = string.format([[
      SELECT table_name, table_type
      FROM information_schema.tables
      WHERE table_schema = '%s'
      ORDER BY table_type, table_name
    ]], schema_name)
  elseif db_type == "mysql" then
    query = [[
      SELECT table_name, table_type
      FROM information_schema.tables
      WHERE table_schema = DATABASE()
      ORDER BY table_type, table_name
    ]]
  elseif db_type == "sqlite" then
    query = [[
      SELECT name as table_name, type as table_type
      FROM sqlite_master
      WHERE type IN ('table', 'view')
      ORDER BY type, name
    ]]
  else
    vim.schedule(function()
      callback({}, nil)
    end)
    return
  end

  executor.execute_async(url, query, function(result, err)
    if err then
      callback({}, err)
      return
    end
    cache.tables[schema_name] = M.parse_tables(result, db_type)
    callback(cache.tables[schema_name], nil)
  end)
end

---@param url string
---@param table_name string
---@param callback fun(columns: Dbab.Column[], err: string|nil)
function M.get_columns_async(url, table_name, callback)
  -- Return cached if valid
  if is_cache_valid(url) and cache.columns[table_name] then
    vim.schedule(function()
      callback(cache.columns[table_name], nil)
    end)
    return
  end

  local db_type = connection.parse_type(url)
  local query = ""

  if db_type == "postgres" then
    query = string.format([[
      SELECT
        c.column_name,
        c.data_type,
        c.is_nullable,
        CASE WHEN pk.column_name IS NOT NULL THEN 'YES' ELSE 'NO' END as is_primary
      FROM information_schema.columns c
      LEFT JOIN (
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = '%s' AND tc.constraint_type = 'PRIMARY KEY'
      ) pk ON c.column_name = pk.column_name
      WHERE c.table_name = '%s' AND c.table_schema = 'public'
      ORDER BY c.ordinal_position
    ]], table_name, table_name)
  elseif db_type == "mysql" then
    query = string.format([[
      SELECT
        column_name,
        data_type,
        is_nullable,
        CASE WHEN column_key = 'PRI' THEN 'YES' ELSE 'NO' END as is_primary
      FROM information_schema.columns
      WHERE table_name = '%s' AND table_schema = DATABASE()
      ORDER BY ordinal_position
    ]], table_name)
  elseif db_type == "sqlite" then
    query = string.format("PRAGMA table_info('%s')", table_name)
  else
    vim.schedule(function()
      callback({}, nil)
    end)
    return
  end

  executor.execute_async(url, query, function(result, err)
    if err then
      callback({}, err)
      return
    end
    cache.columns[table_name] = M.parse_columns(result, db_type)
    callback(cache.columns[table_name], nil)
  end)
end

return M
