--- See lua/dbab/types.lua for type definitions (Dbab.QueryResult)

local M = {}

---@param raw string Raw output from database
---@return Dbab.QueryResult
function M.parse(raw)
  local lines = vim.split(raw, "\n")

  -- Filter out MySQL warnings
  lines = vim.tbl_filter(function(line)
    return not line:match("^mysql: %[Warning%]")
  end, lines)

  local result = {
    columns = {},
    rows = {},
    row_count = 0,
    raw = raw,
  }

  if #lines == 0 then
    return result
  end

  -- PostgreSQL 포맷 파싱
  -- 첫 줄: 컬럼 헤더
  -- 둘째 줄: 구분선 (---)
  -- 나머지: 데이터 행
  -- 마지막: (N rows)

  local header_line = lines[1]
  local separator_line = lines[2] or ""

  -- MySQL 탭 구분 형식 감지 (첫 줄에 탭이 있으면)
  if header_line:find("\t") then
    -- 탭으로 구분된 형식 (MySQL 등)
    result.columns = vim.split(header_line, "\t")
    for i = 2, #lines do
      local line = lines[i]
      if line ~= "" then
        local row = vim.split(line, "\t")
        table.insert(result.rows, row)
      end
    end
    result.row_count = #result.rows
    return result
  end

  -- 구분선으로 컬럼 위치 파악
  if not separator_line:match("^%-") and not separator_line:match("^%+") then
    -- 구분선이 없으면 raw 텍스트 그대로 반환 (헤더 없이)
    result.columns = {}
    for _, line in ipairs(lines) do
      if line ~= "" then
        table.insert(result.rows, { line })
      end
    end
    result.row_count = #result.rows
    return result
  end

  -- 컬럼 위치 계산 (구분선 기준)
  local col_positions = {}
  local pos = 1
  for segment in separator_line:gmatch("[%-]+") do
    local start_pos = separator_line:find(segment, pos, true)
    local end_pos = start_pos + #segment - 1
    table.insert(col_positions, { start = start_pos, finish = end_pos })
    pos = end_pos + 1
  end

  -- 컬럼 이름 추출
  for _, col_pos in ipairs(col_positions) do
    local col_name = header_line:sub(col_pos.start, col_pos.finish)
    col_name = vim.trim(col_name)
    table.insert(result.columns, col_name)
  end

  -- 데이터 행 추출
  for i = 3, #lines do
    local line = lines[i]

    -- (N rows) 패턴이면 종료
    if line:match("^%(%d+ rows?%)") then
      local count = line:match("%((%d+) rows?%)")
      result.row_count = tonumber(count) or #result.rows
      break
    end

    -- 빈 줄 스킵
    if line ~= "" then
      local row = {}
      for _, col_pos in ipairs(col_positions) do
        local cell = ""
        if col_pos.start <= #line then
          cell = line:sub(col_pos.start, math.min(col_pos.finish, #line))
          cell = vim.trim(cell)
        end
        table.insert(row, cell)
      end
      table.insert(result.rows, row)
    end
  end

  if result.row_count == 0 then
    result.row_count = #result.rows
  end

  return result
end

---@param result Dbab.QueryResult
---@return number[] Column widths
function M.calculate_column_widths(result)
  local widths = {}

  -- 컬럼 헤더 너비
  for i, col in ipairs(result.columns) do
    widths[i] = #col
  end

  -- 데이터 셀 너비
  for _, row in ipairs(result.rows) do
    for i, cell in ipairs(row) do
      widths[i] = math.max(widths[i] or 0, #cell)
    end
  end

  return widths
end

return M
