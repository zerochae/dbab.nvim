local executor = require("dbab.core.executor")
local connection = require("dbab.core.connection")
local parser = require("dbab.utils.parser")
local storage = require("dbab.core.storage")
local query_history = require("dbab.core.history")
local config = require("dbab.config")
local icons = require("dbab.ui.icons")

-- Lazy load to avoid circular dependency
---@return table
local function get_sidebar()
  return require("dbab.ui.sidebar")
end

---@return table
local function get_history_ui()
  return require("dbab.ui.history")
end

-- Default layout for fallback
local DEFAULT_LAYOUT = {
  { "sidebar", "editor" },
  { "history", "grid" },
}

--- Validate layout configuration
---@param layout Dbab.Layout
---@return boolean valid, string? error_message
local function validate_layout(layout)
  if not layout or #layout == 0 then
    return false, "Layout is empty"
  end

  local has_editor = false
  local has_grid = false
  local seen = {}

  for _, row in ipairs(layout) do
    if type(row) ~= "table" or #row == 0 then
      return false, "Invalid row in layout"
    end
    for _, comp in ipairs(row) do
      if seen[comp] then
        return false, "Duplicate component: " .. comp
      end
      seen[comp] = true
      if comp == "editor" then has_editor = true end
      if comp == "grid" then has_grid = true end
    end
  end

  if not has_editor then
    return false, "Missing required component: editor"
  end
  if not has_grid then
    return false, "Missing required component: grid"
  end

  return true, nil
end

--- Calculate width for each component in a row
---@param row Dbab.LayoutRow
---@param total_width number
---@return table<string, number> component -> width
local function calculate_row_widths(row, total_width)
  local cfg = config.get()
  local fixed_widths = {
    sidebar = cfg.sidebar.width,
    history = cfg.history.width,
  }

  local fixed_total = 0
  local variable_count = 0

  for _, comp in ipairs(row) do
    if fixed_widths[comp] then
      fixed_total = fixed_total + fixed_widths[comp]
    else
      variable_count = variable_count + 1
    end
  end

  local variable_ratio = (1 - fixed_total) / math.max(1, variable_count)

  local widths = {}
  for _, comp in ipairs(row) do
    local ratio = fixed_widths[comp] or variable_ratio
    widths[comp] = math.floor(total_width * ratio)
  end

  return widths
end


local M = {}

---@type number|nil
M.tab_nr = nil

---@type number|nil
M.sidebar_buf = nil

---@type number|nil
M.sidebar_win = nil

---@type number|nil
M.editor_win = nil

---@type number|nil
M.result_buf = nil

---@type number|nil
M.result_win = nil

---@type number|nil
M.history_buf = nil

---@type number|nil
M.history_win = nil

-- tabbar is now rendered via winbar on editor_win (no separate buffer/window)

---@type string[]
M.history = {}

---@type number
M.history_index = 0

---@type Dbab.QueryResult|nil
M.last_result = nil

---@type string|nil
M.last_query = nil

---@type number|nil
M.last_duration = nil

---@type string|nil
M.last_conn_name = nil

---@type number|nil
M.last_timestamp = nil

---@type number|nil
M.last_grid_width = nil

--- Apply syntax highlighting to SQL query for winbar using treesitter
---@param query string
---@return string highlighted query with statusline syntax
local function highlight_sql_winbar(query)
  -- Escape % for winbar (must be done on final text segments)
  local function escape_percent(str)
    return str:gsub("%%", "%%%%")
  end

  -- Try to use treesitter for accurate highlighting
  local ok, ts_parser = pcall(vim.treesitter.get_string_parser, query, "sql")
  if not ok or not ts_parser then
    return escape_percent(query)
  end

  local tree = ts_parser:parse()[1]
  if not tree then
    return escape_percent(query)
  end

  local root = tree:root()

  -- Get highlights query for SQL
  local hl_query_ok, hl_query = pcall(vim.treesitter.query.get, "sql", "highlights")
  if not hl_query_ok or not hl_query then
    return escape_percent(query)
  end

  -- Collect highlights: {start_col, end_col, hl_group}
  local highlights = {}

  -- Iterate through captures
  for id, node in hl_query:iter_captures(root, query, 0, 1) do
    local name = hl_query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()

    -- Only handle single-line (row 0)
    if start_row == 0 and end_row == 0 then
      -- Use treesitter highlight group directly (e.g., @keyword.sql)
      local hl_group = "@" .. name .. ".sql"
      table.insert(highlights, { start_col = start_col, end_col = end_col, hl = hl_group })
    end
  end

  -- Sort by start position
  table.sort(highlights, function(a, b) return a.start_col < b.start_col end)

  -- Remove overlapping highlights (keep the first one)
  local filtered = {}
  local last_end = -1
  for _, hl in ipairs(highlights) do
    if hl.start_col >= last_end then
      table.insert(filtered, hl)
      last_end = hl.end_col
    end
  end

  -- Build highlighted string
  local result = ""
  local pos = 0
  for _, hl in ipairs(filtered) do
    -- Skip if highlight starts before current position (shouldn't happen after filtering)
    if hl.start_col < pos then
      goto continue
    end
    -- Add unhighlighted text before this highlight
    if hl.start_col > pos then
      result = result .. escape_percent(query:sub(pos + 1, hl.start_col))
    end
    -- Add highlighted text (single % for winbar highlight syntax)
    local text = query:sub(hl.start_col + 1, hl.end_col)
    result = result .. "%#" .. hl.hl .. "#" .. escape_percent(text) .. "%*"
    pos = hl.end_col
    ::continue::
  end
  -- Add remaining text
  if pos < #query then
    result = result .. escape_percent(query:sub(pos + 1))
  end

  return result
end

--- Get text offset (line number column width) for a window
---@param win number
---@return number
local function get_textoff(win)
  local wininfo = vim.fn.getwininfo(win)
  if wininfo and wininfo[1] then
    return wininfo[1].textoff or 0
  end
  return 0
end

--- Format duration for display
---@param ms number|nil
---@return string
local function format_duration(ms)
  if not ms then return "" end
  if ms < 1000 then
    return string.format("%dms", math.floor(ms))
  elseif ms < 60000 then
    return string.format("%.1fs", ms / 1000)
  else
    return string.format("%.1fm", ms / 60000)
  end
end


--- Update result winbar with query info
function M.refresh_result_winbar()
  if not M.result_win or not vim.api.nvim_win_is_valid(M.result_win) then
    return
  end

  local cfg = config.get()

  -- Get actual text offset (includes line numbers, signs, etc.)
  local textoff = get_textoff(M.result_win)
  local indent = string.rep(" ", textoff)

  local winbar_text = "%#DbabHistoryHeader#" .. icons.result .. " Result%*"
  if M.last_query then
    -- Build prefix: [󰆼 dbname]
    local prefix = ""
    local prefix_display = ""
    if M.last_conn_name then
      prefix = "%#NonText#[%#DbabSidebarIconConnection#" .. icons.db_default .. " %#Normal#" .. M.last_conn_name .. "%#NonText#]%* "
      prefix_display = "[" .. icons.db_default .. " " .. M.last_conn_name .. "] "
    end

    -- Build suffix first to calculate available space for query
    local suffix_parts = {}
    local suffix_display_parts = {}
    if M.last_timestamp then
      local time_str = os.date("%H:%M", M.last_timestamp)
      table.insert(suffix_parts, "%#Comment#" .. icons.time .. " " .. time_str .. "%*")
      table.insert(suffix_display_parts, icons.time .. " " .. time_str)
    end
    if M.last_result and M.last_result.row_count then
      table.insert(suffix_parts, "%#DbabSidebarIconTable#" .. icons.rows .. "%* %#DbabNumber#" .. M.last_result.row_count .. " rows%*")
      table.insert(suffix_display_parts, icons.rows .. " " .. M.last_result.row_count .. " rows")
    end
    if M.last_duration then
      table.insert(suffix_parts, "%#Comment#" .. icons.duration .. " " .. format_duration(M.last_duration) .. "%*")
      table.insert(suffix_display_parts, icons.duration .. " " .. format_duration(M.last_duration))
    end

    -- Calculate target width based on header_align setting
    local win_width = vim.api.nvim_win_get_width(M.result_win)
    local available_width = win_width - textoff
    local header_align = cfg.grid.header_align or "fit"

    local target_width
    if header_align == "full" then
      -- Align to window edge
      target_width = available_width
    else
      -- "fit": align to grid width
      local grid_width = M.last_grid_width or cfg.grid.max_width
      target_width = math.min(grid_width, available_width)
    end

    local prefix_len = vim.fn.strdisplaywidth(prefix_display)
    local suffix_display = table.concat(suffix_display_parts, "  ")
    local suffix_len = vim.fn.strdisplaywidth(suffix_display)

    -- Calculate where suffix should start (aligned to grid edge)
    local suffix_start_pos = target_width - suffix_len
    local query_space = suffix_start_pos - prefix_len - 2  -- -2 for spacing

    -- Truncate query to fit available space
    local query = M.last_query:gsub("%s+", " ") -- normalize whitespace
    local query_len = vim.fn.strdisplaywidth(query)

    if query_space < 10 then
      -- Not enough space: just show metadata aligned to window right
      local highlighted = highlight_sql_winbar(query)
      if query_len > 30 then
        -- Truncate to 30 chars
        local truncated = ""
        local len = 0
        for char_idx = 0, vim.fn.strchars(query) - 1 do
          local char = vim.fn.strcharpart(query, char_idx, 1)
          local char_width = vim.fn.strdisplaywidth(char)
          if len + char_width + 1 > 30 then
            break
          end
          truncated = truncated .. char
          len = len + char_width
        end
        highlighted = highlight_sql_winbar(truncated .. "…")
      end
      winbar_text = prefix .. highlighted .. "%=" .. table.concat(suffix_parts, "  ")
    else
      -- Enough space: align suffix to grid edge
      if query_len > query_space then
        local truncated = ""
        local len = 0
        for char_idx = 0, vim.fn.strchars(query) - 1 do
          local char = vim.fn.strcharpart(query, char_idx, 1)
          local char_width = vim.fn.strdisplaywidth(char)
          if len + char_width + 1 > query_space then
            break
          end
          truncated = truncated .. char
          len = len + char_width
        end
        query = truncated .. "…"
        query_len = vim.fn.strdisplaywidth(query)
      end

      local highlighted = highlight_sql_winbar(query)
      local padding = suffix_start_pos - prefix_len - query_len
      padding = math.max(1, padding)
      winbar_text = prefix .. highlighted .. string.rep(" ", padding) .. table.concat(suffix_parts, "  ")
    end
  end

  vim.api.nvim_win_set_option(M.result_win, "winbar", indent .. winbar_text)
end

--- See lua/dbab/types.lua for type definitions (Dbab.QueryTab)

---@type Dbab.QueryTab[]
M.query_tabs = {}

---@type number
M.active_tab = 0

--- Legacy compatibility
---@type number|nil
M.editor_buf = nil


--- Render the tab bar line for winbar (uses statusline syntax for highlights)
-- Fixed total tab width (icon + name + padding)
local TAB_TOTAL_WIDTH = 16
local ICON_WIDTH = 2 -- nerd font icon display width

--- Truncate name if too long
---@param name string
---@param max_width number
---@return string, number truncated name and its display width
local function truncate_name(name, max_width)
  local display_len = vim.fn.strdisplaywidth(name)
  if display_len <= max_width then
    return name, display_len
  end

  -- Truncate with ellipsis
  local chars = vim.fn.strchars(name)
  local truncated = ""
  local len = 0
  for i = 0, chars - 1 do
    local char = vim.fn.strcharpart(name, i, 1)
    local char_width = vim.fn.strdisplaywidth(char)
    if len + char_width + 1 > max_width then
      break
    end
    truncated = truncated .. char
    len = len + char_width
  end
  return truncated .. "…", len + 1
end

-- Fixed padding on both sides
local TAB_PADDING = 2

---@return string
local function render_tabbar()
  if #M.query_tabs == 0 then
    return ""
  end

  local parts = {}
  for i, tab in ipairs(M.query_tabs) do
    local icon = tab.is_saved and (icons.query_file .. " ") or (icons.open_buffer .. " ")
    local is_active = i == M.active_tab

    -- Truncate name if needed
    local max_name_width = TAB_TOTAL_WIDTH - ICON_WIDTH - (TAB_PADDING * 2)
    local name, _ = truncate_name(tab.name, max_name_width)

    -- Build tab with statusline highlight syntax: %#HighlightGroup#text%*
    local tab_parts = {}

    -- Left padding + Icon (same highlight)
    local icon_hl = is_active and "DbabTabActiveIcon" or (tab.is_saved and "DbabTabIconSaved" or "DbabTabIconUnsaved")
    table.insert(tab_parts, "%#" .. icon_hl .. "#" .. string.rep(" ", TAB_PADDING) .. icon .. "%*")

    -- Name + Right padding (same highlight)
    local name_hl = is_active and "DbabTabActive" or "DbabTabInactive"
    table.insert(tab_parts, "%#" .. name_hl .. "#" .. name .. string.rep(" ", TAB_PADDING) .. "%*")

    table.insert(parts, table.concat(tab_parts, ""))
  end

  return table.concat(parts, icons.separator)
end

--- Update the tab bar display (via winbar on editor window)
function M.refresh_tabbar()
  if not M.editor_win or not vim.api.nvim_win_is_valid(M.editor_win) then
    return
  end

  local cfg = config.get()
  if not cfg.editor.show_tabbar then
    vim.api.nvim_win_set_option(M.editor_win, "winbar", "")
    return
  end

  local winbar = render_tabbar()
  vim.api.nvim_win_set_option(M.editor_win, "winbar", winbar)
end

--- Refresh history panel (call when connection changes)
function M.refresh_history()
  if M.history_win and vim.api.nvim_win_is_valid(M.history_win) then
    get_history_ui().render()
  end
end

--- Get current active tab
---@return Dbab.QueryTab|nil
function M.get_active_tab()
  if M.active_tab > 0 and M.active_tab <= #M.query_tabs then
    return M.query_tabs[M.active_tab]
  end
  return nil
end

--- Switch to a specific tab
---@param index number
function M.switch_tab(index)
  if index < 1 or index > #M.query_tabs then
    return
  end

  M.active_tab = index
  local tab = M.query_tabs[index]

  -- Update editor buffer
  if M.editor_win and vim.api.nvim_win_is_valid(M.editor_win) then
    vim.api.nvim_win_set_buf(M.editor_win, tab.buf)
    M.editor_buf = tab.buf
  end

  -- Update buffer name
  local conn_name = tab.conn_name or connection.get_active_name() or "no connection"
  local display_name = tab.is_saved and tab.name or ("*" .. tab.name)
  pcall(vim.api.nvim_buf_set_name, tab.buf, "[dbab] " .. display_name .. " - " .. conn_name)

  M.refresh_tabbar()
  get_sidebar().refresh()
end

--- Switch to next tab
function M.next_tab()
  if #M.query_tabs == 0 then
    return
  end
  local next_idx = M.active_tab % #M.query_tabs + 1
  M.switch_tab(next_idx)
end

--- Switch to previous tab
function M.prev_tab()
  if #M.query_tabs == 0 then
    return
  end
  local prev_idx = (M.active_tab - 2) % #M.query_tabs + 1
  M.switch_tab(prev_idx)
end

--- Close current tab
function M.close_tab()
  if #M.query_tabs == 0 then
    return
  end

  local tab = M.query_tabs[M.active_tab]
  if tab.modified then
    vim.ui.select({ "Save", "Don't Save", "Cancel" }, {
      prompt = "Save changes to '" .. tab.name .. "'?",
    }, function(choice)
      if choice == "Save" then
        M.save_current_query(function(success)
          if success then
            M._do_close_tab()
          end
        end)
      elseif choice == "Don't Save" then
        M._do_close_tab()
      end
      -- Cancel: do nothing
    end)
  else
    M._do_close_tab()
  end
end

function M._do_close_tab()
  local tab = M.query_tabs[M.active_tab]

  -- Delete buffer
  if tab.buf and vim.api.nvim_buf_is_valid(tab.buf) then
    pcall(vim.api.nvim_buf_delete, tab.buf, { force = true })
  end

  -- Remove from list
  table.remove(M.query_tabs, M.active_tab)

  if #M.query_tabs == 0 then
    -- No more tabs, create a new one
    M.create_new_tab()
  else
    -- Switch to previous or first tab
    M.active_tab = math.min(M.active_tab, #M.query_tabs)
    M.switch_tab(M.active_tab)
  end
end

--- Create a new query tab
---@param name? string
---@param content? string
---@param conn_name? string
---@param is_saved? boolean
---@return number tab_index
function M.create_new_tab(name, content, conn_name, is_saved)
  local buf = vim.api.nvim_create_buf(false, true)
  local conn = conn_name or connection.get_active_name() or "no connection"

  -- Generate unique name for new queries
  local tab_name = name
  if not tab_name then
    local count = 1
    for _, t in ipairs(M.query_tabs) do
      if t.name:match("^query%-") then
        count = count + 1
      end
    end
    tab_name = "query-" .. count
  end

  ---@type Dbab.QueryTab
  local tab = {
    buf = buf,
    name = tab_name,
    conn_name = conn,
    modified = false,
    is_saved = is_saved or false,
  }

  table.insert(M.query_tabs, tab)
  M.active_tab = #M.query_tabs

  -- Setup buffer
  vim.api.nvim_buf_set_option(buf, "filetype", "sql")
  vim.api.nvim_buf_set_option(buf, "buftype", "acwrite") -- allows :w via BufWriteCmd
  vim.api.nvim_buf_set_option(buf, "swapfile", false)

  local display_name = is_saved and tab_name or ("*" .. tab_name)
  pcall(vim.api.nvim_buf_set_name, buf, "[dbab] " .. display_name .. " - " .. conn)

  -- Set content
  local lines = content and vim.split(content, "\n") or { "" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Handle :w, :wq, :wa commands
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      M.save_query_by_buf(buf, function(success)
        if success then
          -- Mark buffer as saved (prevents "modified" warning)
          vim.api.nvim_buf_set_option(buf, "modified", false)
        end
      end)
    end,
  })

  -- Track modifications
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      -- Find this tab and mark as modified
      for _, t in ipairs(M.query_tabs) do
        if t.buf == buf and not t.modified then
          t.modified = true
          M.refresh_tabbar()
          break
        end
      end
    end,
  })

  -- Show in editor window
  if M.editor_win and vim.api.nvim_win_is_valid(M.editor_win) then
    vim.api.nvim_win_set_buf(M.editor_win, buf)
    M.editor_buf = buf
  end

  -- Setup keymaps for this buffer
  M.setup_editor_keymaps(buf)

  M.refresh_tabbar()
  get_sidebar().refresh()

  return #M.query_tabs
end

---@param result Dbab.QueryResult
---@param widths number[]
---@return string[], boolean has_header
local function render_result_lines(result, widths)
  local lines = {}
  local has_header = #result.columns > 0

  if has_header then
    local header = ""
    for i, col in ipairs(result.columns) do
      local w = widths[i] or #col
      local padded = col .. string.rep(" ", w - #col)
      header = header .. " " .. padded .. " "
    end
    table.insert(lines, header)
  end

  for _, row in ipairs(result.rows) do
    local line = ""
    for i, cell in ipairs(row) do
      local w = widths[i] or #cell
      local display = cell == "" and "NULL" or cell
      local padded = display .. string.rep(" ", w - #display)
      line = line .. " " .. padded .. " "
    end
    table.insert(lines, line)
  end

  return lines, has_header
end

---@param cell string
---@return string
local function detect_cell_hl(cell)
  if cell == "" or cell:upper() == "NULL" then
    return "DbabNull"
  elseif cell:match("^%-?%d+%.?%d*$") then
    return "DbabNumber"
  elseif cell:match("^[Tt]rue$") or cell:match("^[Ff]alse$") or cell == "t" or cell == "f" then
    return "DbabBoolean"
  elseif cell:match("^%d%d%d%d%-%d%d%-%d%d") then
    return "DbabDateTime"
  elseif cell:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return "DbabUuid"
  elseif cell:match("^[%[{]") then
    return "DbabJson"
  else
    return "DbabString"
  end
end

---@param bufnr number
---@param result Dbab.QueryResult
---@param widths number[]
---@param has_header boolean
local function apply_highlights(bufnr, result, widths, has_header)
  local ns = vim.api.nvim_create_namespace("dbab_result")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local header_offset = has_header and 1 or 0
  local total_lines = #result.rows + header_offset

  if has_header then
    vim.api.nvim_buf_add_highlight(bufnr, ns, "DbabHeader", 0, 0, -1)
  end

  for line_num = header_offset, total_lines - 1 do
    local row_idx = line_num - header_offset + 1
    local row_hl = row_idx % 2 == 1 and "DbabRowOdd" or "DbabRowEven"
    vim.api.nvim_buf_add_highlight(bufnr, ns, row_hl, line_num, 0, -1)
  end

  for row_idx, row in ipairs(result.rows) do
    local line_num = row_idx - 1 + header_offset

    local col_start = 0
    for col_idx, cell in ipairs(row) do
      local w = widths[col_idx] or #cell
      local cell_start = col_start + 1
      local display = cell == "" and "NULL" or cell
      local hl_group = detect_cell_hl(cell)

      vim.api.nvim_buf_add_highlight(bufnr, ns, hl_group, line_num, cell_start, cell_start + #display)

      col_start = col_start + w + 2
    end
  end
end

--- Check if result is an error
---@param raw string
---@return boolean
local function is_error_result(raw)
  return raw:match("^ERROR:") or raw:match("\nERROR:") or raw:match("syntax error")
end

--- Format error for pretty display
---@param raw string
---@return string[] lines, table[] highlights {line, hl_group, col_start, col_end}
local function format_error(raw)
  local lines = {}
  local highlights = {}

  -- Header
  table.insert(lines, "")
  table.insert(lines, " ✗ Query Error")
  table.insert(highlights, { line = 1, hl = "ErrorMsg", col_start = 0, col_end = -1 })
  table.insert(lines, "")

  -- Split raw into lines for parsing
  local raw_lines = vim.split(raw, "\n")
  local found_content = false

  for _, line in ipairs(raw_lines) do
    if line ~= "" then
      if line:match("^ERROR:") then
        -- Error message line
        local msg = line:match("^ERROR:%s*(.+)") or line
        table.insert(lines, "   " .. msg)
        table.insert(highlights, { line = #lines - 1, hl = "Normal", col_start = 0, col_end = -1 })
        found_content = true
      elseif line:match("^LINE %d+:") then
        -- Line info
        table.insert(lines, "")
        table.insert(lines, "   → " .. line)
        table.insert(highlights, { line = #lines - 1, hl = "WarningMsg", col_start = 0, col_end = -1 })
        found_content = true
      elseif line:match("^%s*%^%s*$") then
        -- Pointer line (^)
        table.insert(lines, "     " .. line)
        table.insert(highlights, { line = #lines - 1, hl = "Comment", col_start = 0, col_end = -1 })
        found_content = true
      elseif found_content then
        -- Additional context
        table.insert(lines, "   " .. line)
        table.insert(highlights, { line = #lines - 1, hl = "Comment", col_start = 0, col_end = -1 })
      end
    end
  end

  -- If parsing failed, show raw error
  if not found_content then
    for _, line in ipairs(raw_lines) do
      if line ~= "" then
        table.insert(lines, "   " .. line)
        table.insert(highlights, { line = #lines - 1, hl = "Normal", col_start = 0, col_end = -1 })
      end
    end
  end

  table.insert(lines, "")

  return lines, highlights
end

--- Check if result is a mutation (UPDATE/DELETE/INSERT/CREATE/DROP/ALTER/TRUNCATE)
---@param raw string
---@return boolean, string|nil verb, number|nil count
local function parse_mutation_result(raw)
  local line = vim.trim(raw)

  -- PostgreSQL: UPDATE N, DELETE N, INSERT 0 N
  local update_count = line:match("^UPDATE%s+(%d+)")
  if update_count then
    return true, "UPDATE", tonumber(update_count)
  end

  local delete_count = line:match("^DELETE%s+(%d+)")
  if delete_count then
    return true, "DELETE", tonumber(delete_count)
  end

  local insert_count = line:match("^INSERT%s+%d+%s+(%d+)")
  if insert_count then
    return true, "INSERT", tonumber(insert_count)
  end

  -- DDL statements
  if line:match("^CREATE") then
    return true, "CREATE", nil
  end
  if line:match("^DROP") then
    return true, "DROP", nil
  end
  if line:match("^ALTER") then
    return true, "ALTER", nil
  end
  if line:match("^TRUNCATE") then
    return true, "TRUNCATE", nil
  end

  return false, nil, nil
end

--- Format mutation result for pretty display
---@param verb string
---@param count number|nil
---@return string[] lines, table[] highlights
local function format_mutation_result(verb, count)
  local lines = {}
  local highlights = {}

  -- Icons and colors per verb
  local verb_config = {
    UPDATE = { icon = icons.mut_update, hl = "DbabHistoryUpdate", label = "updated" },
    DELETE = { icon = icons.mut_delete, hl = "DbabHistoryDelete", label = "deleted" },
    INSERT = { icon = icons.mut_insert, hl = "DbabHistoryInsert", label = "inserted" },
    CREATE = { icon = icons.mut_create, hl = "DbabHistoryCreate", label = "created" },
    DROP = { icon = icons.mut_delete, hl = "DbabHistoryDelete", label = "dropped" },
    ALTER = { icon = icons.mut_update, hl = "DbabHistoryAlter", label = "altered" },
    TRUNCATE = { icon = icons.mut_delete, hl = "DbabHistoryTruncate", label = "truncated" },
  }

  local cfg = verb_config[verb] or { icon = "✓", hl = "String", label = "completed" }

  table.insert(lines, "")

  -- Main result line
  local result_line
  if count then
    local row_word = count == 1 and "row" or "rows"
    result_line = string.format(" %s %d %s %s", cfg.icon, count, row_word, cfg.label)
  else
    result_line = string.format(" %s %s successful", cfg.icon, verb)
  end
  table.insert(lines, result_line)
  table.insert(highlights, { line = 1, hl = cfg.hl, col_start = 0, col_end = -1 })

  table.insert(lines, "")

  return lines, highlights
end

--- Save query by buffer number
---@param buf number
---@param callback? fun(success: boolean)
function M.save_query_by_buf(buf, callback)
  local tab = nil
  for _, t in ipairs(M.query_tabs) do
    if t.buf == buf then
      tab = t
      break
    end
  end
  if not tab then
    if callback then callback(false) end
    return
  end

  local conn_name = tab.conn_name or connection.get_active_name()
  if not conn_name then
    vim.notify("[dbab] No connection for query", vim.log.levels.WARN)
    if callback then callback(false) end
    return
  end

  -- Get content
  local lines = vim.api.nvim_buf_get_lines(tab.buf, 0, -1, false)
  local content = table.concat(lines, "\n")

  local function do_save(name)
    local ok, err = storage.save_query(conn_name, name, content)
    if ok then
      tab.name = name
      tab.modified = false
      tab.is_saved = true
      M.refresh_tabbar()
      get_sidebar().refresh()
      vim.notify("[dbab] Saved: " .. name, vim.log.levels.INFO)
      if callback then callback(true) end
    else
      vim.notify("[dbab] Save failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      if callback then callback(false) end
    end
  end

  -- If already saved, just save with same name
  if tab.is_saved then
    do_save(tab.name)
  else
    -- Prompt for name (vim.schedule for proper focus with UI plugins like snacks.nvim)
    vim.schedule(function()
      vim.ui.input({
        prompt = "Query name: ",
        default = tab.name:match("^query%-") and "" or tab.name,
      }, function(input)
      if input and input ~= "" then
        -- Check if already exists
        if storage.query_exists(conn_name, input) then
          vim.ui.select({ "Overwrite", "Cancel" }, {
            prompt = "Query '" .. input .. "' already exists",
          }, function(choice)
            if choice == "Overwrite" then
              do_save(input)
            else
              if callback then callback(false) end
            end
          end)
        else
          do_save(input)
        end
      else
        if callback then callback(false) end
      end
      end)
    end)
  end
end

--- Save current query to disk
---@param callback? fun(success: boolean)
function M.save_current_query(callback)
  local tab = M.get_active_tab()
  if not tab then
    vim.notify("[dbab] No active query tab", vim.log.levels.WARN)
    if callback then callback(false) end
    return
  end
  M.save_query_by_buf(tab.buf, callback)
end

--- Open a saved query in a new tab
---@param query_name string
---@param content string
---@param conn_name string
function M.open_saved_query(query_name, content, conn_name)
  if not M.tab_nr or not vim.api.nvim_tabpage_is_valid(M.tab_nr) then
    M.open()
  end

  -- Check if already open
  for i, tab in ipairs(M.query_tabs) do
    if tab.name == query_name and tab.conn_name == conn_name and tab.is_saved then
      M.switch_tab(i)
      -- Focus editor
      if M.editor_win and vim.api.nvim_win_is_valid(M.editor_win) then
        vim.api.nvim_set_current_win(M.editor_win)
      end
      return
    end
  end

  -- Create new tab
  M.create_new_tab(query_name, content, conn_name, true)

  -- Focus editor
  if M.editor_win and vim.api.nvim_win_is_valid(M.editor_win) then
    vim.api.nvim_set_current_win(M.editor_win)
  end
end

---@param raw string
---@param elapsed number
function M.show_result(raw, elapsed)
  if not M.result_buf or not vim.api.nvim_buf_is_valid(M.result_buf) then
    return
  end

  vim.api.nvim_buf_set_option(M.result_buf, "modifiable", true)

  if is_error_result(raw) then
    local lines, highlights = format_error(raw)

    vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)

    if M.result_win and vim.api.nvim_win_is_valid(M.result_win) then
      vim.api.nvim_win_set_option(M.result_win, "number", false)
      vim.api.nvim_win_set_option(M.result_win, "relativenumber", false)
    end

    local ns = vim.api.nvim_create_namespace("dbab_result")
    vim.api.nvim_buf_clear_namespace(M.result_buf, ns, 0, -1)
    for _, hl in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(M.result_buf, ns, hl.hl, hl.line, hl.col_start, hl.col_end)
    end

    vim.notify("[dbab] Query error", vim.log.levels.ERROR)
    return
  end

  local is_mutation, verb, count = parse_mutation_result(raw)
  if is_mutation and verb then
    local lines, highlights = format_mutation_result(verb, count)

    vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)

    if M.result_win and vim.api.nvim_win_is_valid(M.result_win) then
      vim.api.nvim_win_set_option(M.result_win, "number", false)
      vim.api.nvim_win_set_option(M.result_win, "relativenumber", false)
    end

    local ns = vim.api.nvim_create_namespace("dbab_result")
    vim.api.nvim_buf_clear_namespace(M.result_buf, ns, 0, -1)
    for _, hl in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(M.result_buf, ns, hl.hl, hl.line, hl.col_start, hl.col_end)
    end

    M.last_result = { columns = {}, rows = {}, row_count = count or 0, raw = raw }
    M.refresh_result_winbar()

    local status_msg = count and string.format(" %s: %d rows (%.1fms) ", verb, count, elapsed)
      or string.format(" %s successful (%.1fms) ", verb, elapsed)
    vim.notify(status_msg, vim.log.levels.INFO)
    return
  end

  local cfg = config.get()

  if M.result_win and vim.api.nvim_win_is_valid(M.result_win) then
    vim.api.nvim_win_set_option(M.result_win, "number", cfg.grid.show_line_number)
  end

  local result_style = cfg.grid.style or "table"
  local result = parser.parse(raw, result_style)
  M.last_result = result

  pcall(vim.treesitter.stop, M.result_buf)
  vim.api.nvim_buf_set_option(M.result_buf, "filetype", "")

  if result.row_count == 0 then
    vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, { "No results returned" })
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)
    return
  end

  if result_style == "raw" then
    local raw_lines = vim.split(result.raw, "\n")
    vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, raw_lines)
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)
    M.refresh_result_winbar()
    return
  end

  if result_style == "json" then
    local json_lines = vim.split(result.raw, "\n")
    vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, json_lines)
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)
    local ok = pcall(vim.treesitter.start, M.result_buf, "json")
    if not ok then
      vim.api.nvim_buf_set_option(M.result_buf, "filetype", "json")
    end
    M.refresh_result_winbar()
    return
  end

  if result_style == "vertical" then
    local vert_lines = vim.split(result.raw, "\n")
    vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, vert_lines)
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)

    local ns = vim.api.nvim_create_namespace("dbab_result")
    vim.api.nvim_buf_clear_namespace(M.result_buf, ns, 0, -1)

    for i, line in ipairs(vert_lines) do
      local ln = i - 1
      if line:match("^%-%[ RECORD %d+") then
        vim.api.nvim_buf_add_highlight(M.result_buf, ns, "DbabHeader", ln, 0, -1)
      else
        local sep = line:find(" | ")
        if sep then
          local col_name = vim.trim(line:sub(1, sep - 1))
          local col_start = line:find(col_name, 1, true)
          vim.api.nvim_buf_add_highlight(M.result_buf, ns, "DbabKey", ln, col_start - 1, col_start - 1 + #col_name)

          vim.api.nvim_buf_add_highlight(M.result_buf, ns, "DbabBorder", ln, sep - 1, sep + 2)

          local value = vim.trim(line:sub(sep + 3))
          local value_start = sep + 2
          local hl_group = detect_cell_hl(value)
          vim.api.nvim_buf_add_highlight(M.result_buf, ns, hl_group, ln, value_start, value_start + #value)
        end
      end
    end

    M.refresh_result_winbar()
    return
  end

  if result_style == "markdown" then
    local md_lines = vim.split(result.raw, "\n")
    vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, md_lines)
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)
    local ok = pcall(vim.treesitter.start, M.result_buf, "markdown")
    if not ok then
      vim.api.nvim_buf_set_option(M.result_buf, "filetype", "markdown")
    end
    M.refresh_result_winbar()
    return
  end

  local widths = parser.calculate_column_widths(result)
  local lines, has_header = render_result_lines(result, widths)

  -- Calculate actual grid width from column widths
  local grid_width = 0
  for _, w in ipairs(widths) do
    grid_width = grid_width + w + 2 -- +2 for " " padding on each side
  end
  M.last_grid_width = grid_width

  vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)

  apply_highlights(M.result_buf, result, widths, has_header)

  M.refresh_result_winbar()

  local status = string.format(" Result: %d rows (%.1fms) ", result.row_count, elapsed)
  vim.notify(status, vim.log.levels.INFO)

  if M.result_win and vim.api.nvim_win_is_valid(M.result_win) then
    vim.api.nvim_set_current_win(M.result_win)
    pcall(vim.api.nvim_win_set_cursor, M.result_win, { 2, 0 })
    vim.cmd("stopinsert")
  end
end

function M.execute_query()
  if not M.editor_buf or not vim.api.nvim_buf_is_valid(M.editor_buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(M.editor_buf, 0, -1, false)
  local query = table.concat(lines, "\n")
  query = vim.trim(query)

  if query == "" then
    vim.notify("[dbab] Empty query", vim.log.levels.WARN)
    return
  end

  local url = connection.get_active_url()
  if not url then
    vim.notify("[dbab] No active connection", vim.log.levels.WARN)
    return
  end

  table.insert(M.history, 1, query)
  if #M.history > 100 then
    table.remove(M.history)
  end
  M.history_index = 0

  local start_time = vim.loop.hrtime()
  local result = executor.execute(url, query)
  local elapsed = (vim.loop.hrtime() - start_time) / 1e6

  local parsed_result = parser.parse(result)
  query_history.add({
    query = query,
    timestamp = os.time(),
    conn_name = connection.get_active_name() or "unknown",
    duration_ms = elapsed,
    row_count = parsed_result and parsed_result.row_count or 0,
  })

  if M.history_win and vim.api.nvim_win_is_valid(M.history_win) then
    get_history_ui().render()
  end

  M.last_query = query
  M.last_duration = elapsed
  M.last_conn_name = connection.get_active_name()
  M.last_timestamp = os.time()
  M.show_result(result, elapsed)
end

---@return number|nil
local function delete_existing_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name:match(vim.pesc(name)) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
end

function M.open()
  if M.tab_nr and vim.api.nvim_tabpage_is_valid(M.tab_nr) then
    local tabs = vim.api.nvim_list_tabpages()
    for i, tab in ipairs(tabs) do
      if tab == M.tab_nr then
        vim.cmd("tabnext " .. i)
        return
      end
    end
  end

  if M.tab_nr then
    M.cleanup()
  end

  if config._has_legacy_config then
    vim.notify("[dbab] You are using a legacy config (ui.*). Please check the new flat config structure.", vim.log.levels.WARN)
  end

  delete_existing_buf("[dbab]")

  local cfg = config.get()
  local layout = cfg.layout or DEFAULT_LAYOUT

  -- Validate layout
  local valid, err = validate_layout(layout)
  if not valid then
    vim.notify("[dbab] Invalid layout: " .. (err or "unknown") .. ". Using default.", vim.log.levels.WARN)
    layout = DEFAULT_LAYOUT
  end

  vim.cmd("tabnew")
  local initial_buf = vim.api.nvim_get_current_buf()
  M.tab_nr = vim.api.nvim_get_current_tabpage()

  local total_width = vim.o.columns
  local total_height = vim.o.lines - 4
  local row_count = #layout
  local row_height = math.floor(total_height / row_count)

  local windows = {}

  local row_wins = { vim.api.nvim_get_current_win() }

  for row_idx = 2, row_count do
    vim.cmd("belowright split")
    row_wins[row_idx] = vim.api.nvim_get_current_win()
  end

  for row_idx, row in ipairs(layout) do
    local row_win = row_wins[row_idx]
    vim.api.nvim_set_current_win(row_win)

    windows[row[1]] = row_win

    for col_idx = 2, #row do
      local comp = row[col_idx]
      vim.cmd("belowright vsplit")
      windows[comp] = vim.api.nvim_get_current_win()
    end
  end

  for row_idx = 1, row_count - 1 do
    local row = layout[row_idx]
    local first_comp = row[1]
    if windows[first_comp] and vim.api.nvim_win_is_valid(windows[first_comp]) then
      vim.api.nvim_win_set_height(windows[first_comp], row_height)
    end
  end

  for _, row in ipairs(layout) do
    local row_widths = calculate_row_widths(row, total_width)
    for _, comp in ipairs(row) do
      local win = windows[comp]
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_width(win, row_widths[comp])
      end
    end
  end

  M._init_all_components(windows)

  pcall(vim.api.nvim_buf_delete, initial_buf, { force = true })

  if M.sidebar_win and vim.api.nvim_win_is_valid(M.sidebar_win) then
    vim.api.nvim_set_current_win(M.sidebar_win)
  end

  M._setup_autocmds()
end

--- Initialize all components in their windows
---@param windows table<string, number> Component name -> window handle
function M._init_all_components(windows)
  local cfg = config.get()

  -- Sidebar
  if windows.sidebar then
    M.sidebar_win = windows.sidebar
    M.sidebar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(M.sidebar_win, M.sidebar_buf)
    get_sidebar().setup(M.sidebar_buf, M.sidebar_win)
  end

  -- Editor
  if windows.editor then
    M.editor_win = windows.editor
    M.create_new_tab(nil, nil, connection.get_active_name(), false)
  end

  -- Grid (Result)
  if windows.grid then
    M.result_win = windows.grid
    M.result_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(M.result_win, M.result_buf)
    vim.api.nvim_buf_set_name(M.result_buf, "[dbab] Result")
    vim.api.nvim_buf_set_option(M.result_buf, "filetype", "dbab_result")
    vim.api.nvim_buf_set_option(M.result_buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(M.result_buf, "buflisted", false)
    vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)
    vim.api.nvim_win_set_option(M.result_win, "cursorline", true)
    vim.api.nvim_win_set_option(M.result_win, "wrap", false)
    vim.api.nvim_win_set_option(M.result_win, "number", cfg.grid.show_line_number)
    vim.api.nvim_win_set_option(M.result_win, "relativenumber", false)
    M.setup_result_keymaps()
    vim.schedule(function()
      M.refresh_result_winbar()
    end)
  end

  -- History
  if windows.history then
    M.history_win = windows.history
    M.history_buf = get_history_ui().get_or_create_buf()
    vim.api.nvim_win_set_buf(M.history_win, M.history_buf)
    get_history_ui().setup(M.history_win)
  end
end

--- Setup autocmds for workbench
function M._setup_autocmds()
  local augroup = vim.api.nvim_create_augroup("DbabWorkbench", { clear = true })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = augroup,
    callback = function()
      if not vim.api.nvim_tabpage_is_valid(M.tab_nr or 0) then
        M.cleanup()
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(ev)
      if M.tab_nr and vim.api.nvim_get_current_tabpage() ~= M.tab_nr then
        return
      end

      local closed_win = tonumber(ev.match)
      if closed_win == M.editor_win then
        M.editor_win = nil
        M.editor_buf = nil
      end
      if closed_win == M.sidebar_win then
        vim.schedule(function()
          if M.tab_nr and vim.api.nvim_tabpage_is_valid(M.tab_nr) then
            pcall(vim.cmd, "tabclose")
          end
          M.cleanup()
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      if M.tab_nr and vim.api.nvim_get_current_tabpage() == M.tab_nr then
        M._resize_layout()
        get_history_ui().render()
        M.refresh_result_winbar()
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
      if M.tab_nr and vim.api.nvim_get_current_tabpage() == M.tab_nr then
        get_history_ui().render()
        M.refresh_result_winbar()
      end
    end,
  })
end

--- Resize layout based on current window size and config.layout
function M._resize_layout()
  local cfg = config.get()
  local layout = cfg.layout or DEFAULT_LAYOUT
  local total_width = vim.o.columns
  local total_height = vim.o.lines - 4
  local row_count = #layout
  local row_height = math.floor(total_height / row_count)

  local comp_to_win = {
    sidebar = M.sidebar_win,
    editor = M.editor_win,
    history = M.history_win,
    grid = M.result_win,
  }

  for row_idx, row in ipairs(layout) do
    local row_widths = calculate_row_widths(row, total_width)

    for _, comp in ipairs(row) do
      local win = comp_to_win[comp]
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_width(win, row_widths[comp])
        if row_idx < row_count then
          vim.api.nvim_win_set_height(win, row_height)
        end
      end
    end
  end
end

---@param query? string
function M.open_editor(query)
  if not M.tab_nr or not vim.api.nvim_tabpage_is_valid(M.tab_nr) then
    M.open()
  end

  -- Create a new query tab
  M.create_new_tab(nil, query, connection.get_active_name(), false)

  if M.editor_win and vim.api.nvim_win_is_valid(M.editor_win) then
    vim.api.nvim_set_current_win(M.editor_win)
    vim.cmd("startinsert!")
  end
end

---@param query string
function M.open_editor_with_query(query)
  M.open_editor(query)
end

function M.setup_result_keymaps()
  if not M.result_buf then
    return
  end

  local result_opts = { noremap = true, silent = true, buffer = M.result_buf }
  local keymaps = config.get().keymaps.result

  -- Tab: To Sidebar/History
  vim.keymap.set("n", keymaps.to_sidebar, function()
    if M.history_win and vim.api.nvim_win_is_valid(M.history_win) then
      vim.api.nvim_set_current_win(M.history_win)
    elseif M.sidebar_win and vim.api.nvim_win_is_valid(M.sidebar_win) then
      vim.api.nvim_set_current_win(M.sidebar_win)
    end
  end, result_opts)

  -- S-Tab: To Editor
  vim.keymap.set("n", keymaps.to_editor, function()
    if M.editor_win and vim.api.nvim_win_is_valid(M.editor_win) then
      vim.api.nvim_set_current_win(M.editor_win)
    end
  end, result_opts)

  -- y: Yank current row
  vim.keymap.set("n", keymaps.yank_row, function()
    M.yank_current_row()
  end, result_opts)

  -- Y: Yank all rows
  vim.keymap.set("n", keymaps.yank_all, function()
    M.yank_all_rows()
  end, result_opts)

  -- Close
  vim.keymap.set("n", config.get().keymaps.close, function()
    M.close()
  end, result_opts)
end

--- Setup keymaps for a specific editor buffer
---@param buf number
function M.setup_editor_keymaps(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local opts = { noremap = true, silent = true, buffer = buf }
  local keymaps = config.get().keymaps.editor

  -- Enter: Execute query (Normal mode)
  vim.keymap.set("n", config.get().keymaps.execute, function()
    M.execute_query()
  end, opts)

  -- Ctrl+Enter: Execute query (Insert mode)
  vim.keymap.set("i", keymaps.execute_insert, function()
    M.execute_query()
  end, opts)

  -- Leader+r: Execute query
  vim.keymap.set("n", keymaps.execute_leader, function()
    M.execute_query()
  end, opts)

  -- Ctrl+s: Save
  vim.keymap.set("n", keymaps.save, function()
    M.save_current_query()
  end, opts)

  vim.keymap.set("i", keymaps.save, function()
    vim.cmd("stopinsert")
    M.save_current_query()
  end, opts)

  -- gt: Next tab
  vim.keymap.set("n", keymaps.next_tab, function()
    M.next_tab()
  end, opts)

  -- gT: Previous tab
  vim.keymap.set("n", keymaps.prev_tab, function()
    M.prev_tab()
  end, opts)

  -- Leader+w: Close tab
  vim.keymap.set("n", keymaps.close_tab, function()
    M.close_tab()
  end, opts)

  -- Tab: To Result
  vim.keymap.set("n", keymaps.to_result, function()
    if M.result_win and vim.api.nvim_win_is_valid(M.result_win) then
      vim.api.nvim_set_current_win(M.result_win)
    elseif M.sidebar_win and vim.api.nvim_win_is_valid(M.sidebar_win) then
      vim.api.nvim_set_current_win(M.sidebar_win)
    end
  end, opts)

  -- S-Tab: To Sidebar
  vim.keymap.set("n", keymaps.to_sidebar, function()
    if M.sidebar_win and vim.api.nvim_win_is_valid(M.sidebar_win) then
      vim.api.nvim_set_current_win(M.sidebar_win)
    end
  end, opts)

  -- Close
  vim.keymap.set("n", config.get().keymaps.close, function()
    M.close()
  end, opts)
end

function M.setup_keymaps()
  -- Legacy: setup keymaps for current editor_buf
  if M.editor_buf then
    M.setup_editor_keymaps(M.editor_buf)
  end
end

function M.yank_current_row()
  if not M.last_result or not M.result_win then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(M.result_win)
  local row_idx = cursor[1] - 1

  if row_idx < 1 or row_idx > #M.last_result.rows then
    vim.notify("[dbab] No data row selected", vim.log.levels.WARN)
    return
  end

  local row = M.last_result.rows[row_idx]
  local obj = {}
  for i, col in ipairs(M.last_result.columns) do
    obj[col] = row[i]
  end

  local json = vim.fn.json_encode(obj)
  vim.fn.setreg("+", json)
  vim.fn.setreg('"', json)
  vim.notify("[dbab] Row copied as JSON", vim.log.levels.INFO)
end

function M.yank_all_rows()
  if not M.last_result then
    return
  end

  local arr = {}
  for _, row in ipairs(M.last_result.rows) do
    local obj = {}
    for i, col in ipairs(M.last_result.columns) do
      obj[col] = row[i]
    end
    table.insert(arr, obj)
  end

  local json = vim.fn.json_encode(arr)
  vim.fn.setreg("+", json)
  vim.fn.setreg('"', json)
  vim.notify("[dbab] All rows copied as JSON", vim.log.levels.INFO)
end

function M.close()
  if M.tab_nr and vim.api.nvim_tabpage_is_valid(M.tab_nr) then
    vim.cmd("tabclose")
  end
  M.cleanup()
end

function M.cleanup()
  get_sidebar().cleanup()
  get_history_ui().cleanup()

  -- Clean up all query tab buffers
  for _, tab in ipairs(M.query_tabs) do
    if tab.buf and vim.api.nvim_buf_is_valid(tab.buf) then
      pcall(vim.api.nvim_buf_delete, tab.buf, { force = true })
    end
  end

  M.tab_nr = nil
  M.sidebar_buf = nil
  M.sidebar_win = nil
  M.editor_buf = nil
  M.editor_win = nil
  M.result_buf = nil
  M.result_win = nil
  M.history_buf = nil
  M.history_win = nil
  M.last_result = nil
  M.last_query = nil
  M.last_duration = nil
  M.last_conn_name = nil
  M.last_timestamp = nil
  M.last_grid_width = nil
  M.query_tabs = {}
  M.active_tab = 0
end

return M
