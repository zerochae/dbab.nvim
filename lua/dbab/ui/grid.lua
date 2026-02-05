local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local parser = require("dbab.utils.parser")
local config = require("dbab.config")

local M = {}

---@type table|nil
M.current_popup = nil

---@type Dbab.QueryResult|nil
M.current_result = nil

---@type number Current row (1-indexed)
M.cursor_row = 1

---@type number Current column (1-indexed)
M.cursor_col = 1

---@param result Dbab.QueryResult
---@param widths number[]
---@return string[]
local function render_lines(result, widths)
  local lines = {}

  -- 헤더 렌더링 (borderless)
  local header = ""
  for i, col in ipairs(result.columns) do
    local padded = col .. string.rep(" ", widths[i] - #col)
    header = header .. " " .. padded .. " "
  end
  table.insert(lines, header)

  -- 데이터 행 렌더링 (borderless)
  for _, row in ipairs(result.rows) do
    local line = ""
    for i, cell in ipairs(row) do
      local w = widths[i] or #cell
      local padded = cell .. string.rep(" ", w - #cell)
      line = line .. " " .. padded .. " "
    end
    table.insert(lines, line)
  end

  return lines
end

---@param raw string Raw query result
---@param elapsed number Execution time in ms
function M.show(raw, elapsed)
  if M.current_popup then
    M.current_popup:unmount()
    M.current_popup = nil
  end

  local result = parser.parse(raw)
  M.current_result = result
  M.cursor_row = 1
  M.cursor_col = 1

  if #result.rows == 0 then
    vim.notify("[dbab] Query returned no data rows", vim.log.levels.INFO)
    return
  end

  local widths = parser.calculate_column_widths(result)
  local lines = render_lines(result, widths)

  -- 창 크기 계산
  local max_line_width = 0
  for _, line in ipairs(lines) do
    max_line_width = math.max(max_line_width, vim.fn.strdisplaywidth(line))
  end

  local opts = config.get()
  local width = math.min(max_line_width + 4, opts.ui.grid.max_width, vim.o.columns - 10)
  local height = math.min(#lines + 2, opts.ui.grid.max_height, vim.o.lines - 10)

  local popup = Popup({
    position = "50%",
    size = {
      width = width,
      height = height,
    },
    border = {
      style = "rounded",
      text = {
        top = string.format(" Result: %d rows (%.1fms) ", result.row_count, elapsed),
        top_align = "center",
        bottom = " q:close  j/k:scroll  y:yank row ",
        bottom_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:DbabBorder,CursorLine:DbabCellActive",
      cursorline = true,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      filetype = "dbab_result",
    },
  })

  M.current_popup = popup
  popup:mount()

  -- 내용 설정
  vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", false)

  -- Zebra striping 전체 적용
  local total_lines = #lines
  for line_num = 0, total_lines - 1 do
    local row_hl = line_num % 2 == 0 and "DbabRowOdd" or "DbabRowEven"
    vim.api.nvim_buf_add_highlight(popup.bufnr, -1, row_hl, line_num, 0, -1)
  end

  -- 헤더 컬럼명만 DbabHeader로 강조
  local byte_pos = 0
  for i, col in ipairs(result.columns) do
    -- 앞 공백 건너뛰기
    byte_pos = byte_pos + 1
    -- 컬럼 이름만 하이라이트
    vim.api.nvim_buf_add_highlight(popup.bufnr, -1, "DbabHeader", 0, byte_pos, byte_pos + #col)
    -- 다음 셀: value(w) + 공백(1) = w + 1
    byte_pos = byte_pos + widths[i] + 1
  end

  -- 커서를 첫 데이터 행으로 (헤더만 건너뜀)
  vim.api.nvim_win_set_cursor(popup.winid, { 2, 0 })

  -- 키매핑
  M.setup_keymaps(popup)

  -- 포커스 잃으면 닫기
  popup:on(event.BufLeave, function()
    popup:unmount()
    M.current_popup = nil
  end)
end

---@param popup table NuiPopup instance
function M.setup_keymaps(popup)
  local opts = { noremap = true, silent = true }

  -- 닫기
  popup:map("n", "q", function()
    popup:unmount()
    M.current_popup = nil
  end, opts)

  popup:map("n", "<Esc>", function()
    popup:unmount()
    M.current_popup = nil
  end, opts)

  -- 현재 행 yank (JSON 형식)
  popup:map("n", "y", function()
    M.yank_current_row()
  end, opts)

  -- 전체 결과 yank (JSON 형식)
  popup:map("n", "Y", function()
    M.yank_all_rows()
  end, opts)

  -- 행 복사 (CSV)
  popup:map("n", "c", function()
    M.yank_current_row_csv()
  end, opts)
end

function M.yank_current_row()
  if not M.current_result or not M.current_popup then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(M.current_popup.winid)
  local row_idx = cursor[1] - 1 -- 헤더만 건너뜀 (borderless)

  if row_idx < 1 or row_idx > #M.current_result.rows then
    vim.notify("[dbab] No data row selected", vim.log.levels.WARN)
    return
  end

  local row = M.current_result.rows[row_idx]
  local obj = {}
  for i, col in ipairs(M.current_result.columns) do
    obj[col] = row[i]
  end

  local json = vim.fn.json_encode(obj)
  vim.fn.setreg("+", json)
  vim.fn.setreg('"', json)
  vim.notify("[dbab] Row copied as JSON", vim.log.levels.INFO)
end

function M.yank_current_row_csv()
  if not M.current_result or not M.current_popup then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(M.current_popup.winid)
  local row_idx = cursor[1] - 1 -- 헤더만 건너뜀 (borderless)

  if row_idx < 1 or row_idx > #M.current_result.rows then
    vim.notify("[dbab] No data row selected", vim.log.levels.WARN)
    return
  end

  local row = M.current_result.rows[row_idx]
  local csv = table.concat(row, ",")
  vim.fn.setreg("+", csv)
  vim.fn.setreg('"', csv)
  vim.notify("[dbab] Row copied as CSV", vim.log.levels.INFO)
end

function M.yank_all_rows()
  if not M.current_result then
    return
  end

  local arr = {}
  for _, row in ipairs(M.current_result.rows) do
    local obj = {}
    for i, col in ipairs(M.current_result.columns) do
      obj[col] = row[i]
    end
    table.insert(arr, obj)
  end

  local json = vim.fn.json_encode(arr)
  vim.fn.setreg("+", json)
  vim.fn.setreg('"', json)
  vim.notify("[dbab] All rows copied as JSON", vim.log.levels.INFO)
end

return M
