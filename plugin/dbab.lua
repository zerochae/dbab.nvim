if vim.g.loaded_dbab then
  return
end
vim.g.loaded_dbab = true

vim.api.nvim_create_user_command("Dbab", function(opts)
  local dbab = require("dbab")
  local args = opts.fargs

  if #args == 0 then
    dbab.open()
    return
  end

  local subcmd = args[1]

  if subcmd == "connect" then
    if args[2] then
      dbab.connect(args[2])
    else
      -- 인자 없으면 picker 열기
      dbab.pick_connection()
    end
  elseif subcmd == "pick" then
    dbab.pick_connection()
  elseif subcmd == "list" then
    dbab.list_connections()
  elseif subcmd == "query" or subcmd == "q" then
    local query = table.concat(vim.list_slice(args, 2), " ")
    if query == "" then
      vim.notify("[dbab] Usage: :Dbab query <sql>", vim.log.levels.WARN)
      return
    end
    local result = dbab.execute(query)
    if result ~= "" then
      print(result)
    end
  else
    vim.notify("[dbab] Unknown subcommand: " .. subcmd, vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function(arg_lead, cmd_line, _)
    local args = vim.split(cmd_line, "%s+")
    if #args <= 2 then
      local subcommands = { "connect", "pick", "list", "query" }
      return vim.tbl_filter(function(s)
        return s:match("^" .. arg_lead)
      end, subcommands)
    elseif args[2] == "connect" then
      local dbab = require("dbab")
      local connections = dbab.core.connection.list_connections()
      local names = vim.tbl_map(function(c) return c.name end, connections)
      return vim.tbl_filter(function(s)
        return s:match("^" .. arg_lead)
      end, names)
    end
    return {}
  end,
  desc = "Database client for Neovim",
})
