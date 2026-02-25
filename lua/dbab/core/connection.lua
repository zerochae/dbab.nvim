local config = require("dbab.config")

local M = {}

---@type string|nil
M.active_url = nil

---@type string|nil
M.active_name = nil

---@type table<string, boolean>
M.connected_names = {}

---@param url string
---@return string type Database type (postgres, mysql, sqlite, etc.)
function M.parse_type(url)
  if url:match("^postgres") or url:match("^postgresql") then
    return "postgres"
  elseif url:match("^mysql") or url:match("^mariadb") then
    return "mysql"
  elseif url:match("^sqlite") then
    return "sqlite"
  else
    return "unknown"
  end
end

---@param url string
---@return string Resolved URL (환경변수 확장)
function M.resolve_url(url)
  if url:match("^%$") then
    local env_var = url:sub(2)
    local resolved = os.getenv(env_var)
    if resolved then
      return resolved
    end
    vim.notify("[dbab] Environment variable not found: " .. env_var, vim.log.levels.ERROR)
    return url
  end
  return url
end

---@param name string
---@return Dbab.Connection|nil
function M.get_connection_by_name(name)
  local connections = config.get().connections
  for _, conn in ipairs(connections) do
    if conn.name == name then
      return conn
    end
  end
  return nil
end

---@param name string
---@return string|nil
function M.get_resolved_url_by_name(name)
  local conn = M.get_connection_by_name(name)
  if not conn then
    return nil
  end
  return M.resolve_url(conn.url)
end

---@param name string
---@return boolean
function M.set_active(name)
  local conn = M.get_connection_by_name(name)
  if conn then
    M.active_name = conn.name
    M.active_url = M.resolve_url(conn.url)
    M.connected_names[conn.name] = true
    return true
  end
  return false
end

---@param name string
---@return boolean
function M.is_connected(name)
  return M.connected_names[name] == true
end

---@param name string
function M.disconnect(name)
  M.connected_names[name] = nil
  if M.active_name == name then
    M.active_name = nil
    M.active_url = nil
  end
end

function M.reset()
  M.active_url = nil
  M.active_name = nil
  M.connected_names = {}
end

---@return string|nil
function M.get_active_url()
  return M.active_url
end

---@return string|nil
function M.get_active_name()
  return M.active_name
end

---@type fun(): string|nil, string|nil
M.context_provider = nil

---@return string|nil
function M.get_context_url()
  if M.context_provider then
    local _, url = M.context_provider()
    if url then
      return url
    end
  end
  return M.active_url
end

---@return string|nil
function M.get_context_name()
  if M.context_provider then
    local name = M.context_provider()
    if name then
      return name
    end
  end
  return M.active_name
end

---@return Dbab.Connection[]
function M.list_connections()
  return config.get().connections
end

return M
