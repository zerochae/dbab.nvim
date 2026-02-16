local connection = require("dbab.core.connection")

local M = {}

---@param url string
---@return table parsed { scheme, user, password, host, port, database, params }
function M.parse_url(url)
  local result = {}

  local scheme = url:match("^([%w]+)://")
  result.scheme = scheme or "unknown"

  if result.scheme == "sqlite" then
    local path = url:match("^sqlite:///(.+)") or url:match("^sqlite://(.+)")
    if path then
      if path:match("^/") or path:match("^%w+:") or path:match("^~") then
        result.database = path
      elseif path:match("^home/") or path:match("^Users/") or path:match("^tmp/") or path:match("^var/") or path:match("^etc/") or path:match("^usr/") then
        result.database = "/" .. path
      else
        result.database = path
      end
    else
      result.database = ""
    end
    return result
  end

  local rest = url:gsub("^[%w]+://", "")

  local query_string
  rest, query_string = rest:match("^(.-)%?(.+)$")
  if not rest then
    rest = url:gsub("^[%w]+://", "")
  end

  if query_string then
    result.params = {}
    for key, value in query_string:gmatch("([^&=]+)=([^&=]+)") do
      result.params[key] = value
    end
  end

  local auth, hostpath = rest:match("^(.+)@(.+)$")
  if auth then
    local user, password = auth:match("^([^:]+):(.+)$")
    if user then
      result.user = user
      result.password = password
    else
      result.user = auth
    end
    rest = hostpath
  end

  local hostport, database = rest:match("^([^/]+)/(.+)$")
  if hostport then
    local host, port = hostport:match("^(.+):(%d+)$")
    if host then
      result.host = host
      result.port = port
    else
      result.host = hostport
    end
    result.database = database
  else
    result.host = rest
  end

  return result
end

---@param url string
---@return string command
---@return string[] args
function M.build_cmd(url)
  local db_type = connection.parse_type(url)

  if db_type == "postgres" then
    return M._build_postgres(url)
  elseif db_type == "mysql" then
    return M._build_mysql(url)
  elseif db_type == "sqlite" then
    return M._build_sqlite(url)
  end

  error("Unsupported database type: " .. db_type)
end

---@param url string
---@return string command, string[] args
function M._build_postgres(url)
  return "psql", { url }
end

---@param url string
---@return string command, string[] args
function M._build_mysql(url)
  local parsed = M.parse_url(url)
  local command = "mysql"
  local args = {}

  if url:match("^mariadb://") then
    if vim.fn.executable("mariadb") == 1 then
      command = "mariadb"
    elseif vim.fn.executable("mysql") == 1 then
      command = "mysql"
    end
  end

  if parsed.params and parsed.params["login-path"] then
    table.insert(args, "--login-path=" .. parsed.params["login-path"])
  end

  if parsed.host then
    table.insert(args, "-h")
    table.insert(args, parsed.host)
  end
  if parsed.port then
    table.insert(args, "-P")
    table.insert(args, parsed.port)
  end
  if parsed.user then
    table.insert(args, "-u")
    table.insert(args, parsed.user)
  end
  if parsed.password then
    table.insert(args, "-p" .. parsed.password)
  end
  if parsed.database then
    table.insert(args, parsed.database)
  end

  return command, args
end

---@param url string
---@return string command, string[] args
function M._build_sqlite(url)
  local parsed = M.parse_url(url)
  return "sqlite3", { parsed.database }
end

return M
