--- Query storage module for dbab.nvim
--- Stores queries in ~/.local/share/nvim/dbab/queries/{connection_name}/{query_name}.sql
local M = {}

--- Get the base directory for query storage
---@return string
function M.get_queries_dir()
  local data_dir = vim.fn.stdpath("data")
  return data_dir .. "/dbab/queries"
end

--- Get the directory for a specific connection
---@param conn_name string
---@return string
function M.get_connection_dir(conn_name)
  return M.get_queries_dir() .. "/" .. conn_name
end

--- Ensure a directory exists
---@param dir string
---@return boolean success
local function ensure_dir(dir)
  if vim.fn.isdirectory(dir) == 0 then
    local result = vim.fn.mkdir(dir, "p")
    return result == 1
  end
  return true
end

--- Sanitize a filename (remove invalid characters)
---@param name string
---@return string
local function sanitize_filename(name)
  -- Remove or replace characters that are invalid in filenames
  local sanitized = name:gsub("[/\\:*?\"<>|]", "_")
  -- Ensure it doesn't start with a dot
  if sanitized:sub(1, 1) == "." then
    sanitized = "_" .. sanitized
  end
  return sanitized
end

--- Get the full path for a query file
---@param conn_name string
---@param query_name string
---@return string
function M.get_query_path(conn_name, query_name)
  local sanitized = sanitize_filename(query_name)
  -- Add .sql extension if not present
  if not sanitized:match("%.sql$") then
    sanitized = sanitized .. ".sql"
  end
  return M.get_connection_dir(conn_name) .. "/" .. sanitized
end

--- List all saved queries for a connection
---@param conn_name string
---@return {name: string, path: string, modified: number}[]
function M.list_queries(conn_name)
  local dir = M.get_connection_dir(conn_name)
  local queries = {}

  if vim.fn.isdirectory(dir) == 0 then
    return queries
  end

  local files = vim.fn.readdir(dir)
  for _, file in ipairs(files) do
    if file:match("%.sql$") then
      local path = dir .. "/" .. file
      local stat = vim.loop.fs_stat(path)
      local name = file:gsub("%.sql$", "")
      table.insert(queries, {
        name = name,
        path = path,
        modified = stat and stat.mtime.sec or 0,
      })
    end
  end

  -- Sort by modified time (newest first)
  table.sort(queries, function(a, b)
    return a.modified > b.modified
  end)

  return queries
end

--- Save a query to disk
---@param conn_name string
---@param query_name string
---@param content string
---@return boolean success, string? error
function M.save_query(conn_name, query_name, content)
  local dir = M.get_connection_dir(conn_name)

  if not ensure_dir(dir) then
    return false, "Failed to create directory: " .. dir
  end

  local path = M.get_query_path(conn_name, query_name)

  local file = io.open(path, "w")
  if not file then
    return false, "Failed to open file for writing: " .. path
  end

  file:write(content)
  file:close()

  return true, nil
end

--- Load a query from disk
---@param conn_name string
---@param query_name string
---@return string? content, string? error
function M.load_query(conn_name, query_name)
  local path = M.get_query_path(conn_name, query_name)

  local file = io.open(path, "r")
  if not file then
    return nil, "Failed to open file: " .. path
  end

  local content = file:read("*a")
  file:close()

  return content, nil
end

--- Delete a query from disk
---@param conn_name string
---@param query_name string
---@return boolean success, string? error
function M.delete_query(conn_name, query_name)
  local path = M.get_query_path(conn_name, query_name)

  if vim.fn.filereadable(path) == 0 then
    return false, "File not found: " .. path
  end

  local result = vim.fn.delete(path)
  if result ~= 0 then
    return false, "Failed to delete file: " .. path
  end

  return true, nil
end

--- Rename a query
---@param conn_name string
---@param old_name string
---@param new_name string
---@return boolean success, string? error
function M.rename_query(conn_name, old_name, new_name)
  local old_path = M.get_query_path(conn_name, old_name)
  local new_path = M.get_query_path(conn_name, new_name)

  if vim.fn.filereadable(old_path) == 0 then
    return false, "File not found: " .. old_path
  end

  if vim.fn.filereadable(new_path) == 1 then
    return false, "File already exists: " .. new_path
  end

  local result = vim.fn.rename(old_path, new_path)
  if result ~= 0 then
    return false, "Failed to rename file"
  end

  return true, nil
end

--- Check if a query exists
---@param conn_name string
---@param query_name string
---@return boolean
function M.query_exists(conn_name, query_name)
  local path = M.get_query_path(conn_name, query_name)
  return vim.fn.filereadable(path) == 1
end

--- Get the count of saved queries for a connection
---@param conn_name string
---@return number
function M.get_query_count(conn_name)
  local queries = M.list_queries(conn_name)
  return #queries
end

return M
