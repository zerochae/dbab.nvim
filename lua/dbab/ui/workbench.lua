local connection = require("dbab.core.connection")
local config = require("dbab.config")

local result = require("dbab.ui.result")
local keymaps = require("dbab.ui.keymaps")
local tabs = require("dbab.ui.tabs")
local query = require("dbab.ui.query")
local winbar = require("dbab.ui.winbar")

local function get_sidebar()
	return require("dbab.ui.sidebar")
end

local function get_history_ui()
	return require("dbab.ui.history")
end

local DEFAULT_LAYOUT = {
	{ "sidebar", "editor" },
	{ "history", "result" },
}

---@param layout Dbab.LayoutRow[]
---@return boolean valid, string? error_message
local function validate_layout(layout)
	if not layout or #layout == 0 then
		return false, "Layout is empty"
	end

	local has_editor = false
	local has_result = false
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
			if comp == "editor" then
				has_editor = true
			end
			if comp == "result" then
				has_result = true
			end
		end
	end

	if not has_editor then
		return false, "Missing required component: editor"
	end
	if not has_result then
		return false, "Missing required component: result"
	end

	return true, nil
end

---@param row Dbab.LayoutRow
---@param total_width number
---@return table<string, number>
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

---@type number|nil
M.editor_buf = nil

result.setup(M)
winbar.setup(M, result)
keymaps.setup(M)
tabs.setup(M)
query.setup(M)

setmetatable(M, {
	__index = function(_, k)
		if k == "query_tabs" then
			return tabs.query_tabs
		end
		if k == "active_tab" then
			return tabs.active_tab
		end
		if k == "last_result" then
			return result.last_result
		end
		if k == "last_query" then
			return result.last_query
		end
		if k == "last_duration" then
			return result.last_duration
		end
		if k == "last_conn_name" then
			return result.last_conn_name
		end
		if k == "last_timestamp" then
			return result.last_timestamp
		end
		if k == "last_result_width" then
			return result.last_result_width
		end
		if k == "history" then
			return query.history
		end
		if k == "history_index" then
			return query.history_index
		end
	end,
	__newindex = function(t, k, v)
		if k == "active_tab" then
			tabs.active_tab = v
			return
		end
		if k == "last_result" then
			result.last_result = v
			return
		end
		if k == "last_query" then
			result.last_query = v
			return
		end
		if k == "last_duration" then
			result.last_duration = v
			return
		end
		if k == "last_conn_name" then
			result.last_conn_name = v
			return
		end
		if k == "last_timestamp" then
			result.last_timestamp = v
			return
		end
		if k == "last_result_width" then
			result.last_result_width = v
			return
		end
		if k == "history_index" then
			query.history_index = v
			return
		end
		rawset(t, k, v)
	end,
})

function M.refresh_result_winbar()
	winbar.refresh_result()
end

function M.refresh_tabbar()
	tabs.refresh_tabbar()
end

function M.refresh_history()
	tabs.refresh_history()
end

function M.get_active_tab()
	return tabs.get_active_tab()
end

function M.get_active_connection_context()
	local active_tab = M.get_active_tab()
	local conn_name = active_tab and active_tab.conn_name or nil

	if conn_name then
		local url = connection.get_resolved_url_by_name(conn_name)
		if url then
			return conn_name, url
		end
	end

	local fallback_name = connection.get_active_name()
	local fallback_url = connection.get_active_url()
	return fallback_name, fallback_url
end

function M.switch_tab(index)
	tabs.switch_tab(index)
end

function M.next_tab()
	tabs.next_tab()
end

function M.prev_tab()
	tabs.prev_tab()
end

function M.close_tab()
	tabs.close_tab()
end

function M.create_new_tab(name, content, conn_name, is_saved)
	return tabs.create_new_tab(name, content, conn_name, is_saved)
end

function M.show_result(raw, elapsed)
	result.show_result(raw, elapsed)
end

function M.execute_query()
	query.execute_query()
end

function M.save_query_by_buf(buf, callback)
	query.save_query_by_buf(buf, callback)
end

function M.save_current_query(callback)
	query.save_current_query(callback)
end

function M.open_saved_query(query_name, content, conn_name)
	query.open_saved_query(query_name, content, conn_name)
end

function M.setup_result_keymaps()
	keymaps.setup_result_keymaps()
end

function M.setup_editor_keymaps(buf)
	keymaps.setup_editor_keymaps(buf)
end

function M.setup_keymaps()
	keymaps.setup_keymaps()
end

function M.yank_current_row()
	result.yank_current_row()
end

function M.yank_all_rows()
	result.yank_all_rows()
end

function M.open()
	if M.tab_nr and vim.api.nvim_tabpage_is_valid(M.tab_nr) then
		local wins_valid = M.sidebar_win
			and vim.api.nvim_win_is_valid(M.sidebar_win)
			and M.editor_win
			and vim.api.nvim_win_is_valid(M.editor_win)
			and M.result_win
			and vim.api.nvim_win_is_valid(M.result_win)

		if wins_valid then
			local tab_list = vim.api.nvim_list_tabpages()
			for i, tab in ipairs(tab_list) do
				if tab == M.tab_nr then
					vim.cmd("tabnext " .. i)
					return
				end
			end
		end

		M.cleanup()
		pcall(function()
			vim.cmd("tabclose")
		end)
	end

	if M.tab_nr then
		M.cleanup()
	end

	if config._has_legacy_config then
		vim.notify(
			"[dbab] You are using a legacy config (ui.*). Please check the new flat config structure.",
			vim.log.levels.WARN
		)
	end

	query.delete_existing_buf("[dbab]")

	local cfg = config.get()
	local layout = cfg.layout or DEFAULT_LAYOUT
	---@cast layout Dbab.LayoutRow[]

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

---@param windows table<string, number>
function M._init_all_components(windows)
	local cfg = config.get()

	if windows.sidebar then
		M.sidebar_win = windows.sidebar
		M.sidebar_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(M.sidebar_win, M.sidebar_buf)
		get_sidebar().setup(M.sidebar_buf, M.sidebar_win)
	end

	if windows.editor then
		M.editor_win = windows.editor
		M.create_new_tab(nil, nil, connection.get_active_name(), false)
	end

	if windows.result then
		M.result_win = windows.result
		M.result_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(M.result_win, M.result_buf)
		vim.api.nvim_buf_set_name(M.result_buf, "[dbab] Result")
		vim.bo[M.result_buf].filetype = "dbab_result"
		vim.bo[M.result_buf].buftype = "nofile"
		vim.bo[M.result_buf].buflisted = false
		vim.bo[M.result_buf].modifiable = false
		vim.wo[M.result_win].cursorline = true
		vim.wo[M.result_win].wrap = false
		vim.wo[M.result_win].number = cfg.result.show_line_number
		vim.wo[M.result_win].relativenumber = false
		M.setup_result_keymaps()
		vim.schedule(function()
			M.refresh_result_winbar()
		end)
	end

	if windows.history then
		M.history_win = windows.history
		M.history_buf = get_history_ui().get_or_create_buf()
		vim.api.nvim_win_set_buf(M.history_win, M.history_buf)
		get_history_ui().setup(M.history_win)
	end
end

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
						pcall(function()
							vim.cmd("tabclose")
						end)
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

function M._resize_layout()
	local cfg = config.get()
	local layout = cfg.layout or DEFAULT_LAYOUT
	---@cast layout Dbab.LayoutRow[]
	local total_width = vim.o.columns
	local total_height = vim.o.lines - 4
	local row_count = #layout
	local row_height = math.floor(total_height / row_count)

	local comp_to_win = {
		sidebar = M.sidebar_win,
		editor = M.editor_win,
		history = M.history_win,
		result = M.result_win,
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

---@param q? string
function M.open_editor(q)
	if not M.tab_nr or not vim.api.nvim_tabpage_is_valid(M.tab_nr) then
		M.open()
	end

	M.create_new_tab(nil, q, connection.get_active_name(), false)

	if M.editor_win and vim.api.nvim_win_is_valid(M.editor_win) then
		vim.api.nvim_set_current_win(M.editor_win)
		vim.cmd("startinsert!")
	end
end

---@param q string
function M.open_editor_with_query(q)
	M.open_editor(q)
end

function M.restore()
	if M.tab_nr and vim.api.nvim_tabpage_is_valid(M.tab_nr) then
		pcall(function()
			vim.cmd("tabclose")
		end)
	end
	M.cleanup()
	M.open()
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

	tabs.cleanup()
	result.cleanup()
	query.cleanup()

	M.tab_nr = nil
	M.sidebar_buf = nil
	M.sidebar_win = nil
	M.editor_buf = nil
	M.editor_win = nil
	M.result_buf = nil
	M.result_win = nil
	M.history_buf = nil
	M.history_win = nil
end

return M
