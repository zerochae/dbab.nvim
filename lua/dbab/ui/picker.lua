local Menu = require("nui.menu")
local event = require("nui.utils.autocmd").event
local connection = require("dbab.core.connection")

local M = {}

---@param on_select fun(item: Dbab.Connection|nil)
function M.open(on_select)
  local connections = connection.list_connections()

  if #connections == 0 then
    vim.notify("[dbab] No connections configured", vim.log.levels.WARN)
    on_select(nil)
    return
  end

  local lines = {}
  for _, conn in ipairs(connections) do
    local db_type = connection.parse_type(conn.url)
    local icon = M.get_icon(db_type)
    table.insert(lines, Menu.item(icon .. " " .. conn.name, { connection = conn }))
  end

  local menu = Menu({
    position = "50%",
    size = {
      width = 40,
      height = math.min(#connections + 2, 10),
    },
    border = {
      style = "rounded",
      text = {
        top = " Select Connection ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:DbabBorder,CursorLine:DbabCellActive",
    },
  }, {
    lines = lines,
    max_width = 40,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>", "q" },
      submit = { "<CR>", "<Space>" },
    },
    on_submit = function(item)
      on_select(item.connection)
    end,
    on_close = function()
      on_select(nil)
    end,
  })

  menu:mount()

  menu:on(event.BufLeave, function()
    menu:unmount()
  end)
end

---@param db_type string
---@return string
function M.get_icon(db_type)
  local icons = require "dbab.ui.icons"
  return icons.db(db_type)
end

return M
