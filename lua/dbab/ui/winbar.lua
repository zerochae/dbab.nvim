local config = require("dbab.config")
local icons = require("dbab.ui.icons")

local M = {}

local workbench
local result

function M.setup(workbench_ref, result_ref)
	workbench = workbench_ref
	result = result_ref
end

---@param query string
---@return string highlighted query with statusline syntax
local function highlight_sql(query)
	local function escape_percent(str)
		return str:gsub("%%", "%%%%")
	end

	local ok, ts_parser = pcall(vim.treesitter.get_string_parser, query, "sql")
	if not ok or not ts_parser then
		return escape_percent(query)
	end

	local tree = ts_parser:parse()[1]
	if not tree then
		return escape_percent(query)
	end

	local root = tree:root()

	local hl_query_ok, hl_query = pcall(vim.treesitter.query.get, "sql", "highlights")
	if not hl_query_ok or not hl_query then
		return escape_percent(query)
	end

	local highlights = {}

	for id, node in hl_query:iter_captures(root, query, 0, 1) do
		local name = hl_query.captures[id]
		local start_row, start_col, end_row, end_col = node:range()

		if start_row == 0 and end_row == 0 then
			local hl_group = "@" .. name .. ".sql"
			table.insert(highlights, { start_col = start_col, end_col = end_col, hl = hl_group })
		end
	end

	table.sort(highlights, function(a, b)
		return a.start_col < b.start_col
	end)

	local filtered = {}
	local last_end = -1
	for _, hl in ipairs(highlights) do
		if hl.start_col >= last_end then
			table.insert(filtered, hl)
			last_end = hl.end_col
		end
	end

	local out = ""
	local pos = 0
	for _, hl in ipairs(filtered) do
		if hl.start_col < pos then
			goto continue
		end
		if hl.start_col > pos then
			out = out .. escape_percent(query:sub(pos + 1, hl.start_col))
		end
		local text = query:sub(hl.start_col + 1, hl.end_col)
		out = out .. "%#" .. hl.hl .. "#" .. escape_percent(text) .. "%*"
		pos = hl.end_col
		::continue::
	end
	if pos < #query then
		out = out .. escape_percent(query:sub(pos + 1))
	end

	return out
end

---@param win number
---@return number
local function get_textoff(win)
	local wininfo = vim.fn.getwininfo(win)
	if wininfo and wininfo[1] then
		return wininfo[1].textoff or 0
	end
	return 0
end

---@param ms number|nil
---@return string
local function format_duration(ms)
	if not ms then
		return ""
	end
	if ms < 1000 then
		return string.format("%dms", math.floor(ms))
	elseif ms < 60000 then
		return string.format("%.1fs", ms / 1000)
	else
		return string.format("%.1fm", ms / 60000)
	end
end

function M.refresh_result()
	if not workbench.result_win or not vim.api.nvim_win_is_valid(workbench.result_win) then
		return
	end

	local cfg = config.get()

	local textoff = get_textoff(workbench.result_win)
	local indent = string.rep(" ", textoff)

	local winbar_text = "%#DbabHistoryHeader#" .. icons.result .. " Result%*"
	if result.last_query then
		local prefix = ""
		local prefix_display = ""
		if result.last_conn_name then
			prefix = "%#NonText#[%#DbabSidebarIconConnection#"
				.. icons.db_default
				.. " %#Normal#"
				.. result.last_conn_name
				.. "%#NonText#]%* "
			prefix_display = "[" .. icons.db_default .. " " .. result.last_conn_name .. "] "
		end

		local suffix_parts = {}
		local suffix_display_parts = {}
		if result.last_timestamp then
			local time_str = os.date("%H:%M", result.last_timestamp)
			table.insert(suffix_parts, "%#Comment#" .. icons.time .. " " .. time_str .. "%*")
			table.insert(suffix_display_parts, icons.time .. " " .. time_str)
		end
		if result.last_result and result.last_result.row_count then
			table.insert(
				suffix_parts,
				"%#DbabSidebarIconTable#" .. icons.rows .. "%* %#DbabNumber#" .. result.last_result.row_count .. " rows%*"
			)
			table.insert(suffix_display_parts, icons.rows .. " " .. result.last_result.row_count .. " rows")
		end
		if result.last_duration then
			table.insert(suffix_parts, "%#Comment#" .. icons.duration .. " " .. format_duration(result.last_duration) .. "%*")
			table.insert(suffix_display_parts, icons.duration .. " " .. format_duration(result.last_duration))
		end

		local win_width = vim.api.nvim_win_get_width(workbench.result_win)
		local available_width = win_width - textoff
		local header_align = cfg.result.header_align or "fit"

		local target_width
		if header_align == "full" then
			target_width = available_width
		else
			local grid_width = result.last_result_width or cfg.result.max_width
			target_width = math.min(grid_width, available_width)
		end

		local prefix_len = vim.fn.strdisplaywidth(prefix_display)
		local suffix_display = table.concat(suffix_display_parts, "  ")
		local suffix_len = vim.fn.strdisplaywidth(suffix_display)

		local suffix_start_pos = target_width - suffix_len
		local query_space = suffix_start_pos - prefix_len - 2

		local query = result.last_query:gsub("%s+", " ")
		local query_len = vim.fn.strdisplaywidth(query)

		if query_space < 10 then
			local highlighted = highlight_sql(query)
			if query_len > 30 then
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
				highlighted = highlight_sql(truncated .. "…")
			end
			winbar_text = prefix .. highlighted .. "%=" .. table.concat(suffix_parts, "  ")
		else
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

			local highlighted = highlight_sql(query)
			local padding = suffix_start_pos - prefix_len - query_len
			padding = math.max(1, padding)
			winbar_text = prefix .. highlighted .. string.rep(" ", padding) .. table.concat(suffix_parts, "  ")
		end
	end

	vim.wo[workbench.result_win].winbar = indent .. winbar_text
end

return M
