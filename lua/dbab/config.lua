--- See lua/dbab/types.lua for type definitions

local M = {}

--- Layout presets
---@type table<string, { layout: Dbab.Layout, sidebar_width: number, history_width: number }>
M.layout_presets = {
  -- Classic 4-pane layout (default)
  classic = {
    layout = {
      { "sidebar", "editor" },
      { "history", "grid" },
    },
    sidebar_width = 0.2,
    history_width = 0.2,
  },
  -- Wide top layout (3-column top, full-width bottom)
  wide = {
    layout = {
      { "sidebar", "editor", "history" },
      { "grid" },
    },
    sidebar_width = 0.33,
    history_width = 0.33,
  },
}

---@type Dbab.Config
M.defaults = {
  connections = {},
  ui = {
    layout = "classic", -- "classic" | "wide" | Dbab.Layout
    sidebar = {
      width = 0.2,
      use_brand_icon = false,
      use_brand_color = false,
      show_brand_name = false,
    },
    history = {
      width = 0.2,
      style = "compact", -- "compact" = one line per entry, "detailed" = multi-line with full query
    },
    editor = {
      show_tabbar = true,
    },
    grid = {
      max_width = 120,
      max_height = 20,
      show_line_number = true,
      header_align = "fit", -- "fit" = align metadata to grid width, "full" = align to window edge
      style = "table", -- "table" (default), "json", "raw", "vertical", "markdown"
    },
  },
  keymaps = {
    -- Global keymaps
    open = "<Leader>db",
    execute = "<CR>",
    close = "q",

    -- Sidebar keymaps
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

    -- History keymaps
    history = {
      select = "<CR>",
      execute = "R",
      copy = "y",
      delete = "d",
      clear = "C",
      to_sidebar = "<Tab>",
      to_result = "<S-Tab>",
    },

    -- Editor keymaps
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

    -- Result keymaps
    result = {
      yank_row = "y",
      yank_all = "Y",
      to_sidebar = "<Tab>",
      to_editor = "<S-Tab>",
    },
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
  highlights = {},
}

---@type Dbab.Config|nil
M.options = nil

---@param opts? Dbab.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- Apply layout preset if string
  M._apply_layout_preset()
end

--- Apply layout preset if ui.layout is a string
function M._apply_layout_preset()
  if not M.options or not M.options.ui then
    return
  end

  local layout = M.options.ui.layout
  if type(layout) == "string" then
    local preset = M.layout_presets[layout]
    if preset then
      M.options.ui.layout = preset.layout
      -- Only apply preset widths if user didn't override them
      if M.options.ui.sidebar.width == M.defaults.ui.sidebar.width then
        M.options.ui.sidebar.width = preset.sidebar_width
      end
      if M.options.ui.history.width == M.defaults.ui.history.width then
        M.options.ui.history.width = preset.history_width
      end
    else
      vim.notify("[dbab] Unknown layout preset: " .. layout .. ". Using 'classic'.", vim.log.levels.WARN)
      M.options.ui.layout = M.layout_presets.classic.layout
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
