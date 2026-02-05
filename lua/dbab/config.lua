--- See lua/dbab/types.lua for type definitions

local M = {}

---@type Dbab.Config
M.defaults = {
  connections = {},
  ui = {
    sidebar = {
      position = "left",
      width = 0.2,
      show_history = false,
      history_ratio = 0.3,
    },
    history = {
      position = "left",
      width = 0.2,
    },
    grid = {
      max_width = 120,
      max_height = 20,
      show_line_number = true,
      header_align = "fit", -- "fit" = align metadata to grid width, "full" = align to window edge
    },
  },
  keymaps = {
    open = "<Leader>db",
    execute = "<CR>",
  },
  schema = {
    show_system_schemas = true,
  },
  history = {
    max_entries = 100,
    on_select = "execute",
    persist = true,
    filter_by_connection = true,
    format = nil, -- nil = auto: {"time", "query", "duration"} or {"icon", "dbname", "time", "query", "duration"}
    query_display = "auto", -- "short" = "SEL users", "full" = full query with syntax highlight, "auto" = full if fits
    short_hints = { "where", "join", "order", "group", "limit" }, -- hints: ? WHERE, ⋈ JOIN, ↑↓ ORDER, ⊞ GROUP, ↓N LIMIT
  },
}

---@type Dbab.Config|nil
M.options = nil

---@param opts? Dbab.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

---@return Dbab.Config
function M.get()
  if not M.options then
    M.options = vim.tbl_deep_extend("force", {}, M.defaults)
  end
  return M.options
end

return M
