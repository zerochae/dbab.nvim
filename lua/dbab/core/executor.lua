local connection = require("dbab.core.connection")

local M = {}

-- Check if plenary is available
local has_plenary, Job = pcall(require, "plenary.job")

---@param url string DB connection URL
---@param query string SQL query
---@return string result Raw result from dadbod
function M.execute(url, query)
  local ok, result = pcall(function()
    -- db#adapter#dispatch를 사용하여 쿼리 실행
    local cmd_val = vim.fn["db#adapter#dispatch"](url, "interactive")
    
    -- Fallback for mariadb: if missing, try mysql
    if url:match("^mariadb://") then
      local is_mariadb = false
      if type(cmd_val) == "string" and cmd_val:match("^mariadb") then is_mariadb = true end
      if type(cmd_val) == "table" and cmd_val[1] == "mariadb" then is_mariadb = true end
      
      if is_mariadb and vim.fn.executable("mariadb") == 0 and vim.fn.executable("mysql") == 1 then
         local fallback_url = url:gsub("^mariadb://", "mysql://")
         cmd_val = vim.fn["db#adapter#dispatch"](fallback_url, "interactive")
      end
    end

    local cmd = cmd_val
    local lines = vim.fn["db#systemlist"](cmd, query)
    return table.concat(lines, "\n")
  end)

  if not ok then
    vim.notify("[dbab] Query execution failed: " .. tostring(result), vim.log.levels.ERROR)
    return ""
  end

  return result or ""
end

---@param query string SQL query
---@return string result
function M.execute_active(query)
  local url = connection.get_active_url()
  if not url then
    vim.notify("[dbab] No active connection. Use :Dbab connect first.", vim.log.levels.WARN)
    return ""
  end
  return M.execute(url, query)
end

---@param url string
---@param query string
---@param callback fun(result: string, err: string|nil)
function M.execute_async(url, query, callback)
  if not has_plenary then
    -- Fallback to sync execution with vim.schedule
    vim.schedule(function()
      local result = M.execute(url, query)
      callback(result, nil)
    end)
    return
  end

  -- Get command from dadbod
  local ok, cmd = pcall(vim.fn["db#adapter#dispatch"], url, "interactive")
  
  -- Fallback for mariadb scheme if mariadb command is missing
  -- but mysql command is available
  if (not ok or not cmd) and url:match("^mariadb://") then
     if vim.fn.executable("mariadb") == 0 and vim.fn.executable("mysql") == 1 then
        local fallback_url = url:gsub("^mariadb://", "mysql://")
        ok, cmd = pcall(vim.fn["db#adapter#dispatch"], fallback_url, "interactive")
     end
  end

  if not ok or not cmd then
    vim.schedule(function()
      callback("", "Failed to get adapter command")
    end)
    return
  end

  -- Parse command - dadbod returns a list like ["psql", "postgres://..."]
  -- or a string for some adapters
  local command, args

  if type(cmd) == "table" then
    command = cmd[1]
    args = vim.list_slice(cmd, 2)
  elseif type(cmd) == "string" then
    -- Shell command string - need to parse
    local parts = vim.split(cmd, " ")
    command = parts[1]
    args = vim.list_slice(parts, 2)
  else
    vim.schedule(function()
      callback("", "Unknown command format")
    end)
    return
  end

  -- Collect output
  local stdout_results = {}
  local stderr_results = {}

  Job:new({
    command = command,
    args = args,
    writer = query, -- Pass query as stdin
    on_stdout = function(_, data)
      if data then
        table.insert(stdout_results, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        table.insert(stderr_results, data)
      end
    end,
    on_exit = function(_, return_val)
      vim.schedule(function()
        local result = table.concat(stdout_results, "\n")
        local err = #stderr_results > 0 and table.concat(stderr_results, "\n") or nil

        if return_val ~= 0 and err then
          callback("", err)
        else
          callback(result, nil)
        end
      end)
    end,
  }):start()
end

---@param query string SQL query
---@param callback fun(result: string, err: string|nil)
function M.execute_active_async(query, callback)
  local url = connection.get_active_url()
  if not url then
    vim.schedule(function()
      callback("", "No active connection")
    end)
    return
  end
  M.execute_async(url, query, callback)
end

return M
