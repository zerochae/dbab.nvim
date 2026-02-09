--- See lua/dbab/types.lua for type definitions

local M = {}

--- Layout presets
---@type table<string, { layout: Dbab.Layout, sidebar_width: number, history_width: number }>
M.layout_presets = {
  classic = {
    layout = {
      { "sidebar", "editor" },
      { "history", "result" },
    },
    sidebar_width = 0.2,
    history_width = 0.2,
  },
  wide = {
    layout = {
      { "sidebar", "editor", "history" },
      { "result" },
    },
    sidebar_width = 0.33,
    history_width = 0.33,
  },
}

---@type Dbab.Config
M.defaults = {
  connections = {},
  executor = "cli",
  layout = "classic",
  sidebar = {
    width = 0.2,
    use_brand_icon = false,
    use_brand_color = false,
    show_brand_name = false,
    show_system_schemas = true,
  },
  editor = {
    show_tabbar = true,
  },
  result = {
    max_width = 120,
    max_height = 20,
    show_line_number = true,
    header_align = "fit",
    style = "table",
  },
  history = {
    width = 0.2,
    style = "compact",
    max_entries = 100,
    on_select = "execute",
    persist = true,
    filter_by_connection = true,
    format = nil,
    query_display = "auto",
    short_hints = { "where", "join", "order", "group", "limit" },
  },
  keymaps = {
    open = "<Leader>db",
    execute = "<CR>",
    close = "q",

    sidebar = {
      toggle_expand = { "<CR>", "o" },
      refresh = "R",
      rename = "r",
      new_query = "n",
      copy_name = "y",
      insert_template = "i",
      delete = "d",
      copy_query = "c",
      paste_query = "p",
      to_editor = "<Tab>",
      to_history = "<S-Tab>",
    },

    history = {
      select = "<CR>",
      execute = "R",
      copy = "y",
      delete = "d",
      clear = "C",
      to_sidebar = "<Tab>",
      to_result = "<S-Tab>",
    },

    editor = {
      execute_insert = "<C-CR>",
      execute_leader = "<Leader>r",
      save = "<C-s>",
      next_tab = "gt",
      prev_tab = "gT",
      close_tab = "<Leader>w",
      to_result = "<Tab>",
      to_sidebar = "<S-Tab>",
    },

    result = {
      yank_row = "y",
      yank_all = "Y",
      to_sidebar = "<Tab>",
      to_editor = "<S-Tab>",
    },
  },
  highlights = {},
}

---@type Dbab.Config|nil
M.options = nil

M._has_legacy_config = false

--- Migrate legacy ui.* config to flat structure
---@param opts table
---@return table
local function migrate_legacy(opts)
  if not opts.ui then
    return opts
  end

  vim.notify("[dbab] 'ui.*' config is deprecated. Use flat config instead.", vim.log.levels.WARN)
  M._has_legacy_config = true
  local ui = opts.ui
  opts.ui = nil

  if ui.layout and not opts.layout then
    opts.layout = ui.layout
  end
  if ui.sidebar then
    opts.sidebar = vim.tbl_deep_extend("force", opts.sidebar or {}, ui.sidebar)
  end
  if ui.editor then
    opts.editor = vim.tbl_deep_extend("force", opts.editor or {}, ui.editor)
  end
  if ui.grid then
    opts.result = vim.tbl_deep_extend("force", opts.result or {}, ui.grid)
  end
  if ui.result then
    opts.result = vim.tbl_deep_extend("force", opts.result or {}, ui.result)
  end
  if ui.history then
    opts.history = vim.tbl_deep_extend("force", opts.history or {}, ui.history)
  end

  return opts
end

---@param opts? Dbab.Config
function M.setup(opts)
  local user_opts = opts or {}
  user_opts = migrate_legacy(user_opts)
  if user_opts.grid then
    vim.notify("[dbab] 'grid' is deprecated, use 'result' instead.", vim.log.levels.WARN)
    if not user_opts.result then
      user_opts.result = user_opts.grid
    end
    user_opts.grid = nil
  end
  if user_opts.schema then
    vim.notify("[dbab] 'schema' is deprecated, use 'sidebar' instead.", vim.log.levels.WARN)
    user_opts.sidebar = vim.tbl_deep_extend("force", user_opts.sidebar or {}, user_opts.schema)
    user_opts.schema = nil
  end
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, user_opts)
  M._apply_layout_preset()
end

--- Apply layout preset if layout is a string
function M._apply_layout_preset()
  if not M.options then
    return
  end

  local layout = M.options.layout
  if type(layout) == "string" then
    local preset = M.layout_presets[layout]
    if preset then
      M.options.layout = preset.layout
      if M.options.sidebar.width == M.defaults.sidebar.width then
        M.options.sidebar.width = preset.sidebar_width
      end
      if M.options.history.width == M.defaults.history.width then
        M.options.history.width = preset.history_width
      end
    else
      vim.notify("[dbab] Unknown layout preset: " .. layout .. ". Using 'classic'.", vim.log.levels.WARN)
      M.options.layout = M.layout_presets.classic.layout
    end
  end
end

---@return Dbab.Config
function M.get()
  if not M.options then
    M.options = vim.tbl_deep_extend("force", {}, M.defaults)
    M._apply_layout_preset()
  end
  return M.options
end

return M
