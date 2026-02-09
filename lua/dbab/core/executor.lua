local connection = require("dbab.core.connection")
local config = require("dbab.config")

local M = {}

local has_plenary, Job = pcall(require, "plenary.job")

local function use_dadbod()
  return config.get().executor == "dadbod"
end

-- ============================================
-- CLI backend
-- ============================================

---@param url string
---@param query string
---@return string
local function cli_execute(url, query)
  local adapter = require("dbab.core.adapter")
  local command, args = adapter.build_cmd(url)

  local cmd_parts = { command }
  for _, arg in ipairs(args) do
    table.insert(cmd_parts, arg)
  end
  local cmd_str = table.concat(cmd_parts, " ")

  local lines = vim.fn.systemlist(cmd_str, query)
  return table.concat(lines, "\n")
end

---@param url string
---@param query string
---@param callback fun(result: string, err: string|nil)
local function cli_execute_async(url, query, callback)
  if not has_plenary then
    vim.schedule(function()
      local ok, result = pcall(cli_execute, url, query)
      if ok then
        callback(result, nil)
      else
        callback("", tostring(result))
      end
    end)
    return
  end

  local adapter = require("dbab.core.adapter")
  local command, args = adapter.build_cmd(url)

  local stdout_results = {}
  local stderr_results = {}

  Job:new({
    command = command,
    args = args,
    writer = query,
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

-- ============================================
-- Dadbod backend
-- ============================================

---@param url string
---@return table|string|nil cmd
---@return boolean ok
local function dadbod_get_cmd(url)
  local ok, cmd = pcall(vim.fn["db#adapter#dispatch"], url, "interactive")

  if ok and cmd and url:match("^mariadb://") then
    local is_mariadb = false
    if type(cmd) == "string" and cmd:match("^mariadb") then is_mariadb = true end
    if type(cmd) == "table" and cmd[1] == "mariadb" then is_mariadb = true end

    if is_mariadb and vim.fn.executable("mariadb") == 0 and vim.fn.executable("mysql") == 1 then
      local fallback_url = url:gsub("^mariadb://", "mysql://")
      ok, cmd = pcall(vim.fn["db#adapter#dispatch"], fallback_url, "interactive")
    end
  end

  if (not ok or not cmd) and url:match("^mariadb://") then
    if vim.fn.executable("mariadb") == 0 and vim.fn.executable("mysql") == 1 then
      local fallback_url = url:gsub("^mariadb://", "mysql://")
      ok, cmd = pcall(vim.fn["db#adapter#dispatch"], fallback_url, "interactive")
    end
  end

  return cmd, ok
end

---@param url string
---@param query string
---@return string
local function dadbod_execute(url, query)
  local cmd = dadbod_get_cmd(url)
  local lines = vim.fn["db#systemlist"](cmd, query)
  return table.concat(lines, "\n")
end

---@param url string
---@param query string
---@param callback fun(result: string, err: string|nil)
local function dadbod_execute_async(url, query, callback)
  if not has_plenary then
    vim.schedule(function()
      local ok, result = pcall(dadbod_execute, url, query)
      if ok then
        callback(result, nil)
      else
        callback("", tostring(result))
      end
    end)
    return
  end

  local cmd, ok = dadbod_get_cmd(url)
  if not ok or not cmd then
    vim.schedule(function()
      callback("", "Failed to get adapter command")
    end)
    return
  end

  local command, args
  if type(cmd) == "table" then
    command = cmd[1]
    args = vim.list_slice(cmd, 2)
  elseif type(cmd) == "string" then
    local parts = vim.split(cmd, " ")
    command = parts[1]
    args = vim.list_slice(parts, 2)
  else
    vim.schedule(function()
      callback("", "Unknown command format")
    end)
    return
  end

  local stdout_results = {}
  local stderr_results = {}

  Job:new({
    command = command,
    args = args,
    writer = query,
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

-- ============================================
-- Public API
-- ============================================

---@param url string DB connection URL
---@param query string SQL query
---@return string result
function M.execute(url, query)
  local ok, result = pcall(function()
    if use_dadbod() then
      return dadbod_execute(url, query)
    end
    return cli_execute(url, query)
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
  if use_dadbod() then
    dadbod_execute_async(url, query, callback)
  else
    cli_execute_async(url, query, callback)
  end
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
