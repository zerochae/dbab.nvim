--- History UI module for dbab.nvim
--- Renders the history panel in the bottom-left quadrant
local history = require("dbab.core.history")
local config = require("dbab.config")
local connection = require("dbab.core.connection")
local icons = require("dbab.ui.icons")

local M = {}

---@type number|nil
M.buf = nil

---@type number|nil
M.win = nil

---@type table[] entry_line_map: {{start=N, finish=N}, ...} (1-indexed line numbers)
M.entry_line_map = {}

--- Apply treesitter SQL syntax highlighting to a portion of a line
---@param buf number Buffer number
---@param ns number Namespace id
---@param line number Line number (0-indexed)
---@param col_offset number Column offset where the query starts
---@param query_text string The SQL query text to highlight
local function apply_treesitter_highlights(buf, ns, line, col_offset, query_text)
  -- Try to get SQL parser
  local ok, ts_parser = pcall(vim.treesitter.get_string_parser, query_text, "sql")
  if not ok or not ts_parser then
    -- Fallback: no highlighting
    return
  end

  local tree = ts_parser:parse()[1]
  if not tree then
    return
  end

  -- Get highlights query for SQL
  local query_ok, hl_query = pcall(vim.treesitter.query.get, "sql", "highlights")
  if not query_ok or not hl_query then
    return
  end

  local root = tree:root()

  -- Iterate through all captures and apply highlights
  for id, node in hl_query:iter_captures(root, query_text, 0, -1) do
    local name = hl_query.captures[id]
    local start_row, start_col, _, end_col = node:range()

    -- Only process nodes on the first row (single line query)
    if start_row == 0 then
      -- Map treesitter capture names to highlight groups
      local hl_group = "@" .. name .. ".sql"

      -- Apply highlight with column offset
      pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl_group, line, col_offset + start_col, col_offset + end_col)
    end
  end
end

--- Apply treesitter SQL syntax highlighting to multi-line query text
---@param buf number Buffer number
---@param ns number Namespace id
---@param start_line number First buffer line (0-indexed) where query starts
---@param first_line_offset number Column offset for the first line only
---@param other_line_offset number Column offset for subsequent lines
---@param query_text string The full multi-line SQL query text
local function apply_multiline_treesitter_highlights(buf, ns, start_line, first_line_offset, other_line_offset, query_text)
  local ok, ts_parser = pcall(vim.treesitter.get_string_parser, query_text, "sql")
  if not ok or not ts_parser then
    return
  end

  local tree = ts_parser:parse()[1]
  if not tree then
    return
  end

  local query_ok, hl_query = pcall(vim.treesitter.query.get, "sql", "highlights")
  if not query_ok or not hl_query then
    return
  end

  local root = tree:root()
  local query_lines = vim.split(query_text, "\n")

  for id, node in hl_query:iter_captures(root, query_text, 0, -1) do
    local name = hl_query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()
    local hl_group = "@" .. name .. ".sql"

    if start_row == end_row then
      local offset = start_row == 0 and first_line_offset or other_line_offset
      pcall(
        vim.api.nvim_buf_add_highlight,
        buf,
        ns,
        hl_group,
        start_line + start_row,
        offset + start_col,
        offset + end_col
      )
    else
      for row = start_row, end_row do
        local offset = row == 0 and first_line_offset or other_line_offset
        local s_col, e_col
        if row == start_row then
          s_col = start_col
          e_col = #(query_lines[row + 1] or "")
        elseif row == end_row then
          s_col = 0
          e_col = end_col
        else
          s_col = 0
          e_col = #(query_lines[row + 1] or "")
        end
        pcall(
          vim.api.nvim_buf_add_highlight,
          buf,
          ns,
          hl_group,
          start_line + row,
          offset + s_col,
          offset + e_col
        )
      end
    end
  end
end

--- Create or get the history buffer
---@return number buf
function M.get_or_create_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end

  M.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf, "filetype", "dbab_history")
  vim.api.nvim_buf_set_option(M.buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(M.buf, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(M.buf, "swapfile", false)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
  vim.api.nvim_buf_set_name(M.buf, "[dbab-history]")

  return M.buf
end

--- Render entries in compact mode (one line per entry)
---@param entries Dbab.HistoryEntry[]
---@param win_width number
---@param cfg table
---@return string[] lines, table[] highlights, table[] entry_line_map
local function render_compact(entries, win_width, cfg)
  local r_lines = {}
  local r_highlights = {}
  local r_line_map = {}

  local CONN_NAME_WIDTH = 8
  ---@param name string
  ---@return string
  local function fit_conn_name(name)
    local display_len = vim.fn.strdisplaywidth(name)
    if display_len > CONN_NAME_WIDTH then
      local truncated = ""
      local len = 0
      for i = 0, vim.fn.strchars(name) - 1 do
        local char = vim.fn.strcharpart(name, i, 1)
        local char_width = vim.fn.strdisplaywidth(char)
        if len + char_width + 1 > CONN_NAME_WIDTH then
          break
        end
        truncated = truncated .. char
        len = len + char_width
      end
      return truncated .. "…" .. string.rep(" ", CONN_NAME_WIDTH - len - 1)
    else
      return name .. string.rep(" ", CONN_NAME_WIDTH - display_len)
    end
  end

  --- Get treesitter highlights for short format (verb + target)
  --- Parses original query and extracts keyword/identifier highlights
  ---@param query string Original SQL query
  ---@return string verb_hl Highlight group for verb
  ---@return string target_hl Highlight group for target
  local function get_short_highlights(query)
    local verb_hl = "@keyword.sql"
    local target_hl = "@variable.sql"

    -- Try to parse original query with treesitter
    local ok, ts_parser = pcall(vim.treesitter.get_string_parser, query, "sql")
    if not ok or not ts_parser then
      return verb_hl, target_hl
    end

    local tree = ts_parser:parse()[1]
    if not tree then
      return verb_hl, target_hl
    end

    local query_ok, hl_query = pcall(vim.treesitter.query.get, "sql", "highlights")
    if not query_ok or not hl_query then
      return verb_hl, target_hl
    end

    local root = tree:root()

    -- Find first keyword (SELECT/INSERT/UPDATE/DELETE) and first identifier (table name)
    local found_keyword = false
    local found_identifier = false

    for id, _ in hl_query:iter_captures(root, query, 0, -1) do
      local name = hl_query.captures[id]

      if not found_keyword and name:match("keyword") then
        verb_hl = "@" .. name .. ".sql"
        found_keyword = true
      end

      -- Look for identifier/table after keyword
      if found_keyword and not found_identifier then
        if name:match("variable") or name:match("identifier") or name:match("type") then
          target_hl = "@" .. name .. ".sql"
          found_identifier = true
        end
      end

      if found_keyword and found_identifier then
        break
      end
    end

    return verb_hl, target_hl
  end

  --- Get query hints based on config
  ---@param query string
  ---@return string hints text
  ---@return table[] hint_positions {hint, symbol_start, symbol_end, value_start, value_end}
  local function get_query_hints(query)
    local hints = cfg.history.short_hints or {}
    local hint_set = {}
    for _, h in ipairs(hints) do
      hint_set[h] = true
    end

    local result = ""
    local positions = {}
    local upper_query = query:upper()

    -- WHERE hint with column name
    if hint_set["where"] and upper_query:match("%sWHERE%s") then
      -- Extract first column name after WHERE (handles alias.column format)
      local where_col = query:match("%sWHERE%s+[%w_]+%.([%w_]+)") -- alias.column -> column
        or query:match("%swhere%s+[%w_]+%.([%w_]+)")
        or query:match("%sWHERE%s+([%w_]+)")  -- just column
        or query:match("%swhere%s+([%w_]+)")
      local symbol_start = #result + 1 -- after space
      result = result .. " ?"
      local symbol_end = #result
      if where_col then
        local value_start = #result + 1
        result = result .. " " .. where_col
        table.insert(positions, { hint = "where", symbol_start = symbol_start, symbol_end = symbol_end, value_start = value_start, value_end = #result })
      else
        table.insert(positions, { hint = "where", symbol_start = symbol_start, symbol_end = symbol_end })
      end
    end

    -- JOIN hint with table name
    if hint_set["join"] and upper_query:match("%sJOIN%s") then
      -- Extract joined table name
      local join_table = query:match("%sJOIN%s+([%w_]+)") or query:match("%sjoin%s+([%w_]+)")
      local symbol_start = #result + 1
      result = result .. " ⋈"
      local symbol_end = #result
      if join_table then
        local value_start = #result + 1
        result = result .. " " .. join_table
        table.insert(positions, { hint = "join", symbol_start = symbol_start, symbol_end = symbol_end, value_start = value_start, value_end = #result })
      else
        table.insert(positions, { hint = "join", symbol_start = symbol_start, symbol_end = symbol_end })
      end
    end

    -- ORDER BY hint with column and direction
    if hint_set["order"] then
      local order_col = query:match("%sORDER%s+BY%s+[%w_]+%.([%w_]+)")
        or query:match("%sorder%s+by%s+[%w_]+%.([%w_]+)")
        or query:match("%sORDER%s+BY%s+([%w_]+)")
        or query:match("%sorder%s+by%s+([%w_]+)")
      if order_col then
        local direction = upper_query:match("%sORDER%s+BY%s+[%w_.]+%s+(DESC)") and "↓" or "↑"
        local symbol_start = #result + 1
        result = result .. " " .. direction
        local symbol_end = #result
        local value_start = #result + 1
        result = result .. " " .. order_col
        table.insert(positions, { hint = "order", symbol_start = symbol_start, symbol_end = symbol_end, value_start = value_start, value_end = #result })
      end
    end

    -- GROUP BY hint with column
    if hint_set["group"] then
      local group_col = query:match("%sGROUP%s+BY%s+[%w_]+%.([%w_]+)")
        or query:match("%sgroup%s+by%s+[%w_]+%.([%w_]+)")
        or query:match("%sGROUP%s+BY%s+([%w_]+)")
        or query:match("%sgroup%s+by%s+([%w_]+)")
      if group_col then
        local symbol_start = #result + 1
        result = result .. " ⊞"
        local symbol_end = #result
        local value_start = #result + 1
        result = result .. " " .. group_col
        table.insert(positions, { hint = "group", symbol_start = symbol_start, symbol_end = symbol_end, value_start = value_start, value_end = #result })
      end
    end

    -- LIMIT hint (number only, no separate value)
    if hint_set["limit"] then
      local limit_num = upper_query:match("%sLIMIT%s+(%d+)")
      if limit_num then
        local symbol_start = #result + 1
        result = result .. " ↓" .. limit_num
        table.insert(positions, { hint = "limit", symbol_start = symbol_start, symbol_end = #result })
      end
    end

    return result, positions
  end

  -- Determine format to use
  local format = cfg.history.format
  if not format then
    -- Auto format based on filter_by_connection
    if cfg.history.filter_by_connection then
      format = { "time", "query", "duration" }
    else
      format = { "icon", "dbname", "time", "query", "duration" }
    end
  end

  -- Check which fields are in format
  local has_field = {}
  for _, field in ipairs(format) do
    has_field[field] = true
  end

  for i, entry in ipairs(entries) do
    local _, verb = history.format_summary(entry)
    local icon = history.get_verb_icon(verb)
    local time_str = os.date("%H:%M", entry.timestamp)
    local target = history.get_query_target(entry)
    local duration = history.format_duration(entry.duration_ms)
    local conn_icon = icons.db_default

    -- Build line and track highlight positions
    local line = ""
    local field_positions = {} -- {field, start_byte, end_byte}

    for _, field in ipairs(format) do
      local start_pos = #line

      if field == "icon" then
        -- Use DB icon if dbname is in format, otherwise verb icon
        if has_field.dbname then
          line = line .. "[" .. conn_icon .. " "
        else
          line = line .. icon
        end
        table.insert(field_positions, { field = "icon", verb = verb, start = start_pos, finish = #line })
      elseif field == "dbname" and entry.conn_name then
        local fitted_name = fit_conn_name(entry.conn_name)
        line = line .. fitted_name .. "] "
        table.insert(field_positions, { field = "dbname", start = start_pos, finish = start_pos + #fitted_name })
      elseif field == "time" then
        line = line .. time_str .. " "
        table.insert(field_positions, { field = "time", start = start_pos, finish = start_pos + #time_str })
      elseif field == "query" then
        local query_text
        local use_full = false
        local available_width = win_width - vim.fn.strdisplaywidth(line) - 15 -- reserve for duration

        -- Determine display mode
        local display_mode = cfg.history.query_display
        if display_mode == "auto" then
          -- Auto: use full if query fits, otherwise short
          local full_query = entry.query:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
          if vim.fn.strdisplaywidth(full_query) <= available_width then
            display_mode = "full"
          else
            display_mode = "short"
          end
        end

        local hints_text = ""
        local hint_positions = {}

        if display_mode == "full" then
          -- Full query: normalize whitespace and truncate to fit
          query_text = entry.query:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
          if vim.fn.strdisplaywidth(query_text) > available_width then
            -- Truncate with ellipsis
            local truncated = ""
            local len = 0
            for char_idx = 0, vim.fn.strchars(query_text) - 1 do
              local char = vim.fn.strcharpart(query_text, char_idx, 1)
              local char_width = vim.fn.strdisplaywidth(char)
              if len + char_width + 1 > available_width then
                break
              end
              truncated = truncated .. char
              len = len + char_width
            end
            query_text = truncated .. "…"
          end
          use_full = true
        else
          -- Short: verb + target (e.g., "SEL users") + hints
          query_text = verb .. " " .. target
          hints_text, hint_positions = get_query_hints(entry.query)
        end
        line = line .. query_text .. hints_text
        table.insert(field_positions, {
          field = "query",
          verb = verb,
          target = target,
          start = start_pos,
          query_end = start_pos + #query_text,
          finish = #line,
          full_query = entry.query,
          is_full = use_full,
          hints = hint_positions,
          hints_offset = start_pos + #query_text,
        })
      elseif field == "duration" and duration ~= "" then
        -- Duration is right-aligned, add padding
        local padding = math.max(1, win_width - vim.fn.strdisplaywidth(line) - #duration - 1)
        line = line .. string.rep(" ", padding) .. duration
        table.insert(field_positions, { field = "duration", start = #line - #duration, finish = #line })
      end
    end

    table.insert(r_lines, line)

    -- Compact: each entry is exactly one line
    r_line_map[i] = { start = i, finish = i }

    -- Highlights for this line (0-indexed, no header in buffer)
    local line_idx = i - 1

    -- Zebra striping background
    local row_hl = (i % 2 == 1) and "DbabHistoryRowOdd" or "DbabHistoryRowEven"
    table.insert(r_highlights, { line = line_idx, hl = row_hl, col_start = 0, col_end = -1 })

    -- Apply field-specific highlights
    for _, pos in ipairs(field_positions) do
      if pos.field == "icon" then
        local hl = has_field.dbname and "DbabSidebarIconConnection" or "DbabHistoryVerb"
        table.insert(r_highlights, { line = line_idx, hl = hl, col_start = pos.start, col_end = pos.finish })
      elseif pos.field == "dbname" then
        table.insert(r_highlights, { line = line_idx, hl = "DbabHistoryConnName", col_start = pos.start, col_end = pos.finish })
      elseif pos.field == "time" then
        table.insert(r_highlights, { line = line_idx, hl = "DbabHistoryTime", col_start = pos.start, col_end = pos.finish })
      elseif pos.field == "query" then
        if pos.is_full then
          -- Full mode: direct treesitter highlighting
          table.insert(r_highlights, {
            line = line_idx,
            hl = "treesitter_query",
            col_start = pos.start,
            col_end = pos.query_end,
            query_text = r_lines[line_idx + 1]:sub(pos.start + 1, pos.query_end),
          })
        else
          -- Short mode: parse original query and map highlights to short format
          local verb_hl, target_hl = get_short_highlights(pos.full_query)
          local verb_end = pos.start + #pos.verb
          -- Verb highlight
          table.insert(r_highlights, {
            line = line_idx,
            hl = verb_hl,
            col_start = pos.start,
            col_end = verb_end,
          })
          -- Target highlight
          if pos.target and #pos.target > 0 then
            table.insert(r_highlights, {
              line = line_idx,
              hl = target_hl,
              col_start = verb_end + 1,
              col_end = pos.query_end,
            })
          end
          -- Hint highlights: symbol uses @keyword.sql, value uses @variable.member.sql
          if pos.hints and #pos.hints > 0 then
            for _, hint in ipairs(pos.hints) do
              -- Symbol highlight (?, ⋈, ↑, ↓, ⊞) with @keyword.sql
              table.insert(r_highlights, {
                line = line_idx,
                hl = "@keyword.sql",
                col_start = pos.hints_offset + hint.symbol_start,
                col_end = pos.hints_offset + hint.symbol_end,
              })
              -- Value highlight (column/table name) with @variable.member.sql
              if hint.value_start and hint.value_end then
                table.insert(r_highlights, {
                  line = line_idx,
                  hl = "@variable.member.sql",
                  col_start = pos.hints_offset + hint.value_start,
                  col_end = pos.hints_offset + hint.value_end,
                })
              end
            end
          end
        end
      elseif pos.field == "duration" then
        table.insert(r_highlights, { line = line_idx, hl = "DbabHistoryDuration", col_start = pos.start, col_end = pos.finish })
      end
    end
  end

  return r_lines, r_highlights, r_line_map
end

--- Render entries in detailed mode (multi-line with full query)
---@param entries Dbab.HistoryEntry[]
---@param win_width number
---@param cfg table
---@return string[] lines, table[] highlights, table[] entry_line_map
local function render_detailed(entries, win_width, cfg)
  local r_lines = {}
  local r_highlights = {}
  local r_line_map = {}

  local CONN_NAME_WIDTH = 8
  ---@param name string
  ---@return string
  local function fit_conn_name(name)
    local display_len = vim.fn.strdisplaywidth(name)
    if display_len > CONN_NAME_WIDTH then
      local truncated = ""
      local len = 0
      for idx = 0, vim.fn.strchars(name) - 1 do
        local char = vim.fn.strcharpart(name, idx, 1)
        local char_width = vim.fn.strdisplaywidth(char)
        if len + char_width + 1 > CONN_NAME_WIDTH then
          break
        end
        truncated = truncated .. char
        len = len + char_width
      end
      return truncated .. "…"
    else
      return name
    end
  end

  local sep = " · "

  for i, entry in ipairs(entries) do
    local entry_start = #r_lines + 1

    local _, verb = history.format_summary(entry)
    local verb_icon = history.get_verb_icon(verb)

    local query_lines = vim.split(entry.query, "\n")
    local query_start_line = #r_lines

    for qi, qline in ipairs(query_lines) do
      if qi == 1 then
        table.insert(r_lines, verb_icon .. qline)
      else
        table.insert(r_lines, qline)
      end
    end

    table.insert(r_highlights, {
      line = query_start_line,
      hl = "treesitter_multiline",
      query_text = entry.query,
      start_line = query_start_line,
      first_line_offset = #verb_icon,
      other_line_offset = 0,
    })

    table.insert(r_highlights, { line = query_start_line, hl = "DbabHistoryVerb", col_start = 0, col_end = #verb_icon })

    local time_str = os.date("%H:%M", entry.timestamp)
    local duration = history.format_duration(entry.duration_ms)
    local row_count = entry.row_count
    local show_conn = not cfg.history.filter_by_connection

    local meta_parts = {}
    if show_conn then
      local conn_icon = icons.db_default
      local fitted_name = fit_conn_name(entry.conn_name or "unknown")
      table.insert(meta_parts, { text = conn_icon .. " " .. fitted_name, hl = "DbabHistoryConnName" })
    end
    table.insert(meta_parts, { text = time_str, hl = "DbabHistoryTime" })
    if row_count and row_count > 0 then
      local row_word = row_count == 1 and "row" or "rows"
      table.insert(meta_parts, { text = "󰓫 " .. row_count .. " " .. row_word, hl = "DbabHistoryDuration" })
    end
    if duration ~= "" then
      table.insert(meta_parts, { text = duration, hl = "DbabHistoryDuration" })
    end

    local meta_line = "  "
    local meta_highlights = {}
    for j, part in ipairs(meta_parts) do
      if j > 1 then
        local sep_start = #meta_line
        meta_line = meta_line .. sep
        table.insert(meta_highlights, { start = sep_start, finish = #meta_line, hl = "NonText" })
      end
      local part_start = #meta_line
      meta_line = meta_line .. part.text
      table.insert(meta_highlights, { start = part_start, finish = #meta_line, hl = part.hl })
    end

    table.insert(r_lines, meta_line)
    local meta_line_idx = #r_lines - 1

    table.insert(r_highlights, { line = meta_line_idx, hl = "NonText", col_start = 0, col_end = -1 })
    for _, mh in ipairs(meta_highlights) do
      table.insert(r_highlights, { line = meta_line_idx, hl = mh.hl, col_start = mh.start, col_end = mh.finish })
    end

    local entry_finish = #r_lines
    r_line_map[i] = { start = entry_start, finish = entry_finish }

    if i < #entries then
      local sep_line = string.rep("┄", win_width)
      table.insert(r_lines, sep_line)
      table.insert(r_highlights, { line = #r_lines - 1, hl = "WinSeparator", col_start = 0, col_end = -1 })
    end
  end

  return r_lines, r_highlights, r_line_map
end

--- Render the history buffer
function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end

  local cfg = config.get()
  local all_entries = history.get_all()
  local entries = {}

  if cfg.history.filter_by_connection then
    local current_conn = connection.get_active_name()
    if current_conn then
      for _, entry in ipairs(all_entries) do
        if entry.conn_name == current_conn then
          table.insert(entries, entry)
        end
      end
    end
  else
    entries = all_entries
  end

  local lines = {}
  local highlights = {}

  local winbar_text = "%#DbabHistoryHeader#" .. icons.history .. " " .. "History%*"
  if cfg.history.filter_by_connection then
    local current_conn = connection.get_active_name()
    if current_conn then
      local conn_icon = icons.db_default .. " "
      winbar_text = "%#DbabHistoryHeader#" .. icons.history .. " " .. "History %#NonText#[%#DbabSidebarIconConnection#" .. conn_icon .. "%#Normal#" .. current_conn .. "%#NonText#]%*"
    end
  end
  -- Set winbar
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_set_option(M.win, "winbar", winbar_text)
  end

  -- History entries
  local win_width = 30
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    win_width = vim.api.nvim_win_get_width(M.win)
  end

  if #entries == 0 then
    local empty_msg = "  No history yet"
    if cfg.history.filter_by_connection and not connection.get_active_name() then
      empty_msg = "  Connect to DB first"
    end
    table.insert(lines, empty_msg)
    table.insert(highlights, { line = 0, hl = "Comment", col_start = 0, col_end = -1 })
  else
    local style = cfg.ui.history.style or "compact"
    local render_lines, render_highlights, line_map

    if style == "detailed" then
      render_lines, render_highlights, line_map = render_detailed(entries, win_width, cfg)
    else
      render_lines, render_highlights, line_map = render_compact(entries, win_width, cfg)
    end

    M.entry_line_map = line_map
    for _, l in ipairs(render_lines) do
      table.insert(lines, l)
    end
    for _, h in ipairs(render_highlights) do
      table.insert(highlights, h)
    end
  end

  -- Update buffer
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("dbab_history")
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    if hl.hl == "treesitter_query" and hl.query_text then
      -- Apply single-line treesitter SQL syntax highlighting (compact mode)
      apply_treesitter_highlights(M.buf, ns, hl.line, hl.col_start, hl.query_text)
    elseif hl.hl == "treesitter_multiline" and hl.query_text then
      -- Apply multi-line treesitter SQL syntax highlighting (detailed mode)
      apply_multiline_treesitter_highlights(M.buf, ns, hl.start_line, hl.first_line_offset or 0, hl.other_line_offset or 0, hl.query_text)
    else
      pcall(vim.api.nvim_buf_add_highlight, M.buf, ns, hl.hl, hl.line, hl.col_start, hl.col_end)
    end
  end
end

--- Get filtered entries (same logic as render)
---@return Dbab.HistoryEntry[]
local function get_filtered_entries()
  local cfg = config.get()
  local all_entries = history.get_all()

  if cfg.history.filter_by_connection then
    local current_conn = connection.get_active_name()
    if current_conn then
      local filtered = {}
      for _, entry in ipairs(all_entries) do
        if entry.conn_name == current_conn then
          table.insert(filtered, entry)
        end
      end
      return filtered
    end
    return {}
  end

  return all_entries
end

--- Get entry at current cursor position
---@return Dbab.HistoryEntry|nil, number|nil
function M.get_entry_at_cursor()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then
    return nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(M.win)
  local line = cursor[1] -- 1-indexed

  local entries = get_filtered_entries()

  -- Use entry_line_map to find which entry the cursor is on
  local entry_idx = nil
  if #M.entry_line_map > 0 then
    for i, range in ipairs(M.entry_line_map) do
      if line >= range.start and line <= range.finish then
        entry_idx = i
        break
      end
    end
  else
    -- Fallback for when line map is not yet populated (compact default)
    entry_idx = line
  end

  if entry_idx and entry_idx >= 1 and entry_idx <= #entries then
    return entries[entry_idx], entry_idx
  end

  return nil, nil
end

--- Setup keymaps for history buffer
---@param buf number
function M.setup_keymaps(buf)
  local opts = { buffer = buf, noremap = true, silent = true }
  local keymaps = config.get().keymaps.history

  -- Enter: load or execute
  vim.keymap.set("n", keymaps.select, function()
    M.on_select()
  end, opts)

  -- Re-execute
  vim.keymap.set("n", keymaps.execute, function()
    M.execute_entry()
  end, opts)

  -- Copy query
  vim.keymap.set("n", keymaps.copy, function()
    local entry = M.get_entry_at_cursor()
    if entry then
      vim.fn.setreg("+", entry.query)
      vim.fn.setreg('"', entry.query)
      vim.notify("[dbab] Query copied", vim.log.levels.INFO)
    end
  end, opts)

  -- Delete entry
  vim.keymap.set("n", keymaps.delete, function()
    local entry, idx = M.get_entry_at_cursor()
    if entry and idx then
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Delete this history entry?",
      }, function(choice)
        if choice == "Yes" then
          history.delete(idx)
          M.render()
        end
      end)
    end
  end, opts)

  -- Clear history
  vim.keymap.set("n", keymaps.clear, function()
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Clear all history?",
    }, function(choice)
      if choice == "Yes" then
        history.clear()
        M.render()
        vim.notify("[dbab] History cleared", vim.log.levels.INFO)
      end
    end)
  end, opts)

  -- Close
  vim.keymap.set("n", config.get().keymaps.close, function()
    local workbench = require("dbab.ui.workbench")
    workbench.close()
  end, opts)

  -- Tab: To Sidebar
  vim.keymap.set("n", keymaps.to_sidebar, function()
    local workbench = require("dbab.ui.workbench")
    if workbench.sidebar_win and vim.api.nvim_win_is_valid(workbench.sidebar_win) then
      vim.api.nvim_set_current_win(workbench.sidebar_win)
    end
  end, opts)

  -- S-Tab: To Result
  vim.keymap.set("n", keymaps.to_result, function()
    local workbench = require("dbab.ui.workbench")
    if workbench.result_win and vim.api.nvim_win_is_valid(workbench.result_win) then
      vim.api.nvim_set_current_win(workbench.result_win)
    end
  end, opts)
end

--- Handle entry selection (load or execute based on config)
function M.on_select()
  local entry = M.get_entry_at_cursor()
  if not entry then
    return
  end

  local cfg = config.get()
  if cfg.history.on_select == "execute" then
    M.execute_entry()
  else
    M.load_entry()
  end
end

--- Load entry into editor
function M.load_entry()
  local entry = M.get_entry_at_cursor()
  if not entry then
    return
  end

  local workbench = require("dbab.ui.workbench")
  workbench.open_editor_with_query(entry.query)
end

--- Execute entry immediately
function M.execute_entry()
  local entry = M.get_entry_at_cursor()
  if not entry then
    return
  end

  local workbench = require("dbab.ui.workbench")
  local _, verb = history.format_summary(entry)

  local function do_execute()
    workbench.open_editor_with_query(entry.query)
    vim.schedule(function()
      workbench.execute_query()
    end)
  end

  if verb == "SEL" then
    do_execute()
  else
    local verb_names = {
      INS = "INSERT",
      UPD = "UPDATE",
      DEL = "DELETE",
      CRT = "CREATE",
      DRP = "DROP",
      ALT = "ALTER",
      TRC = "TRUNCATE",
    }
    local verb_name = verb_names[verb] or verb
    vim.ui.select({ "Execute", "Cancel" }, {
      prompt = "Execute " .. verb_name .. " query?",
    }, function(choice)
      if choice == "Execute" then
        do_execute()
      end
    end)
  end
end

--- Setup the history window
---@param win number
function M.setup(win)
  M.win = win
  local buf = M.get_or_create_buf()
  vim.api.nvim_win_set_buf(win, buf)

  -- Window options (must set AFTER buffer is attached to window)
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")
  vim.api.nvim_win_set_option(win, "foldcolumn", "0")
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "winfixwidth", true)

  -- Setup keymaps
  M.setup_keymaps(buf)

  -- Load and render
  history.load()
  M.render()
end

--- Cleanup
function M.cleanup()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    pcall(vim.api.nvim_buf_delete, M.buf, { force = true })
  end
  M.buf = nil
  M.win = nil
  M.entry_line_map = {}
end

return M
