local M = {}

---@param hex string|nil
---@param amount number (negative = darker, positive = lighter)
---@param blue_tint? number (add blue tint, default 0)
---@return string|nil
local function adjust_color(hex, amount, blue_tint)
  if not hex or hex == "" then
    return nil
  end
  blue_tint = blue_tint or 0
  -- Remove # if present
  hex = hex:gsub("^#", "")
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)

  r = math.max(0, math.min(255, r + amount))
  g = math.max(0, math.min(255, g + amount))
  b = math.max(0, math.min(255, b + amount + blue_tint))

  return string.format("#%02x%02x%02x", r, g, b)
end

---@return string|nil
local function get_normal_bg()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
  if normal.bg then
    return string.format("#%06x", normal.bg)
  end
  return nil
end

function M.setup()
  -- Calculate zebra colors based on Normal background
  local normal_bg = get_normal_bg()

  -- Fallback colors if Normal bg is not available
  local row_odd_bg, row_even_bg
  if normal_bg then
    row_odd_bg = adjust_color(normal_bg, -10, 15)  -- darker + blue tint
    row_even_bg = adjust_color(normal_bg, 5, 25)   -- lighter + more blue tint
  else
    -- Fallback: use CursorLine bg or hardcoded dark colors
    local cursorline = vim.api.nvim_get_hl(0, { name = "CursorLine" })
    if cursorline.bg then
      row_odd_bg = string.format("#%06x", cursorline.bg)
      row_even_bg = adjust_color(row_odd_bg, 15)
    else
      -- Ultimate fallback for dark themes (blue tint)
      row_odd_bg = "#1e2230"
      row_even_bg = "#282c3f"
    end
  end

  -- Zebra highlights always update
  vim.api.nvim_set_hl(0, "DbabRowOdd", { bg = row_odd_bg })
  vim.api.nvim_set_hl(0, "DbabRowEven", { bg = row_even_bg })

  -- Header: blue bg, black text (get blue from Function highlight)
  local func_hl = vim.api.nvim_get_hl(0, { name = "Function" })
  local header_bg = func_hl.fg and string.format("#%06x", func_hl.fg) or "#61afef"
  vim.api.nvim_set_hl(0, "DbabHeader", { bg = header_bg, fg = "#000000", bold = true })

  local highlights = {
    -- Window
    DbabFloat = { link = "NormalFloat" },
    DbabBorder = { link = "WinSeparator" },
    DbabTitle = { link = "Title" },

    -- Grid
    DbabSeparator = { link = "Comment" },
    DbabCellActive = { link = "CursorLine" },

    -- Data Types
    DbabNull = { link = "Comment" },
    DbabNumber = { link = "Number" },
    DbabString = { link = "Normal" },
    DbabBoolean = { link = "Boolean" },
    DbabDateTime = { link = "Special" },
    DbabUuid = { link = "Constant" },
    DbabJson = { link = "Function" },

    -- Schema
    DbabTable = { link = "Type" },
    DbabKey = { link = "Keyword" },
    DbabPK = { link = "DiagnosticError", bold = true },
    DbabFK = { link = "Function", bold = true },

    -- Sidebar (DB type icons)
    DbabIconDb = { link = "Number" },
    DbabIconPostgres = { fg = "#4169E1", bold = true },
    DbabIconMysql = { fg = "#4479A1", bold = true },
    DbabIconSqlite = { fg = "#003B57", bold = true },
    DbabIconMariadb = { fg = "#003545", bold = true },
    DbabIconRedis = { fg = "#FF4438", bold = true },
    DbabIconMongodb = { fg = "#47A248", bold = true },

    -- Sidebar (icon colors)
    DbabSidebarIconConnection = { link = "Number" },
    DbabSidebarIconActive = { link = "String" },
    DbabSidebarIconNewQuery = { link = "Function" },
    DbabSidebarIconBuffers = { link = "Function" },
    DbabSidebarIconSaved = { link = "Keyword" },
    DbabSidebarIconSchemas = { link = "Special" },
    DbabSidebarIconSchema = { link = "Type" },
    DbabSidebarIconTable = { link = "Type" },
    DbabSidebarIconColumn = { link = "Function" },
    DbabSidebarIconPK = { link = "ErrorMsg" },
    -- Sidebar (text)
    DbabSidebarText = { link = "Normal" },
    DbabSidebarTextActive = { link = "String", bold = true },
    DbabSidebarType = { link = "Comment" },

    -- History
    DbabHistoryHeader = { link = "Title", bold = true },
    DbabHistoryRowOdd = { bg = row_odd_bg },
    DbabHistoryRowEven = { bg = row_even_bg },
    DbabHistoryTime = { link = "Comment" },
    DbabHistoryVerb = { link = "Keyword" },
    DbabHistoryTarget = { link = "Type" },
    DbabHistoryDuration = { link = "Number" },
    DbabHistoryConnName = { link = "Normal" },
    DbabHistorySelect = { link = "Function" },
    DbabHistoryInsert = { link = "String" },
    DbabHistoryUpdate = { link = "Type" },
    DbabHistoryDelete = { link = "ErrorMsg" },
    DbabHistoryCreate = { link = "String" },
    DbabHistoryDrop = { link = "ErrorMsg" },
    DbabHistoryAlter = { link = "Special" },
    DbabHistoryTruncate = { link = "WarningMsg" },
    -- History hints
    DbabHistoryHintWhere = { link = "WarningMsg" },
    DbabHistoryHintJoin = { link = "Special" },
    DbabHistoryHintOrder = { link = "Keyword" },
    DbabHistoryHintGroup = { link = "Type" },
    DbabHistoryHintLimit = { link = "Number" },

    -- Tab bar
    DbabTabActive = { bg = "#3a3a4a", bold = true },
    DbabTabActiveIcon = { bg = "#3a3a4a", fg = "#a6e3a1" },
    DbabTabInactive = { link = "Comment" },
    DbabTabInactiveIcon = { link = "Comment" },
    DbabTabModified = { link = "WarningMsg" },
    DbabTabIconSaved = { link = "String" },
    DbabTabIconUnsaved = { link = "Function" },
    DbabTabbarBg = { link = "Normal" },
  }

  for name, opts in pairs(highlights) do
    local existing = vim.api.nvim_get_hl(0, { name = name })
    if vim.tbl_isempty(existing) then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  local cfg = require("dbab.config").get()
  if cfg.highlights then
    for name, opts in pairs(cfg.highlights) do
      vim.api.nvim_set_hl(0, name, opts)
    end
  end
end

return M
