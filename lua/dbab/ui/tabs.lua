local connection = require("dbab.core.connection")
local config = require("dbab.config")
local icons = require("dbab.ui.icons")

local function get_sidebar()
	return require("dbab.ui.sidebar")
end

local M = {}

local workbench

function M.setup(workbench_ref)
	workbench = workbench_ref
end

---@type Dbab.QueryTab[]
M.query_tabs = {}

---@type number
M.active_tab = 0

local TAB_TOTAL_WIDTH = 16
local ICON_WIDTH = 2
local TAB_PADDING = 2

---@param name string
---@param max_width number
---@return string, number
local function truncate_name(name, max_width)
	local display_len = vim.fn.strdisplaywidth(name)
	if display_len <= max_width then
		return name, display_len
	end

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

---@return string
local function render_tabbar()
	if #M.query_tabs == 0 then
		return ""
	end

	local parts = {}
	for i, tab in ipairs(M.query_tabs) do
		local icon = tab.is_saved and (icons.query_file .. " ") or (icons.open_buffer .. " ")
		local is_active = i == M.active_tab

		local max_name_width = TAB_TOTAL_WIDTH - ICON_WIDTH - (TAB_PADDING * 2)
		local name, _ = truncate_name(tab.name, max_name_width)

		local tab_parts = {}

		local icon_hl = is_active and "DbabTabActiveIcon" or (tab.is_saved and "DbabTabIconSaved" or "DbabTabIconUnsaved")
		table.insert(tab_parts, "%#" .. icon_hl .. "#" .. string.rep(" ", TAB_PADDING) .. icon .. "%*")

		local name_hl = is_active and "DbabTabActive" or "DbabTabInactive"
		table.insert(tab_parts, "%#" .. name_hl .. "#" .. name .. string.rep(" ", TAB_PADDING) .. "%*")

		table.insert(parts, table.concat(tab_parts, ""))
	end

	return table.concat(parts, icons.separator)
end

function M.refresh_tabbar()
	if not workbench.editor_win or not vim.api.nvim_win_is_valid(workbench.editor_win) then
		return
	end

	local cfg = config.get()
	if not cfg.editor.show_tabbar then
		vim.wo[workbench.editor_win].winbar = ""
		return
	end

	local winbar = render_tabbar()
	vim.wo[workbench.editor_win].winbar = winbar
end

function M.refresh_history()
	local get_history_ui = function()
		return require("dbab.ui.history")
	end
	if workbench.history_win and vim.api.nvim_win_is_valid(workbench.history_win) then
		get_history_ui().render()
	end
end

---@return Dbab.QueryTab|nil
function M.get_active_tab()
	if M.active_tab > 0 and M.active_tab <= #M.query_tabs then
		return M.query_tabs[M.active_tab]
	end
	return nil
end

---@param index number
function M.switch_tab(index)
	if index < 1 or index > #M.query_tabs then
		return
	end

	M.active_tab = index
	local tab = M.query_tabs[index]

	if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
		vim.api.nvim_win_set_buf(workbench.editor_win, tab.buf)
		workbench.editor_buf = tab.buf
	end

	local conn_name = tab.conn_name or connection.get_active_name() or "no connection"
	local display_name = tab.is_saved and tab.name or ("*" .. tab.name)
	pcall(vim.api.nvim_buf_set_name, tab.buf, "[dbab] " .. display_name .. " - " .. conn_name)

	M.refresh_tabbar()
	get_sidebar().refresh()
end

function M.next_tab()
	if #M.query_tabs == 0 then
		return
	end
	local next_idx = M.active_tab % #M.query_tabs + 1
	M.switch_tab(next_idx)
end

function M.prev_tab()
	if #M.query_tabs == 0 then
		return
	end
	local prev_idx = (M.active_tab - 2) % #M.query_tabs + 1
	M.switch_tab(prev_idx)
end

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
				workbench.save_current_query(function(success)
					if success then
						M._do_close_tab()
					end
				end)
			elseif choice == "Don't Save" then
				M._do_close_tab()
			end
		end)
	else
		M._do_close_tab()
	end
end

function M._do_close_tab()
	local tab = M.query_tabs[M.active_tab]

	if tab.buf and vim.api.nvim_buf_is_valid(tab.buf) then
		pcall(vim.api.nvim_buf_delete, tab.buf, { force = true })
	end

	table.remove(M.query_tabs, M.active_tab)

	if #M.query_tabs == 0 then
		M.create_new_tab()
	else
		M.active_tab = math.min(M.active_tab, #M.query_tabs)
		M.switch_tab(M.active_tab)
	end
end

---@param name? string
---@param content? string
---@param conn_name? string
---@param is_saved? boolean
---@return number tab_index
function M.create_new_tab(name, content, conn_name, is_saved)
	local buf = vim.api.nvim_create_buf(false, true)
	local conn = conn_name or connection.get_active_name() or "no connection"

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

	vim.bo[buf].filetype = "sql"
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].swapfile = false

	local display_name = is_saved and tab_name or ("*" .. tab_name)
	pcall(vim.api.nvim_buf_set_name, buf, "[dbab] " .. display_name .. " - " .. conn)

	local lines = content and vim.split(content, "\n") or { "" }
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			workbench.save_query_by_buf(buf, function(success)
				if success then
					vim.bo[buf].modified = false
				end
			end)
		end,
	})

	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function()
			for _, t in ipairs(M.query_tabs) do
				if t.buf == buf and not t.modified then
					t.modified = true
					M.refresh_tabbar()
					break
				end
			end
		end,
	})

	if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
		vim.api.nvim_win_set_buf(workbench.editor_win, buf)
		workbench.editor_buf = buf
	end

	workbench.setup_editor_keymaps(buf)

	M.refresh_tabbar()
	get_sidebar().refresh()

	return #M.query_tabs
end

function M.cleanup()
	for _, tab in ipairs(M.query_tabs) do
		if tab.buf and vim.api.nvim_buf_is_valid(tab.buf) then
			pcall(vim.api.nvim_buf_delete, tab.buf, { force = true })
		end
	end
	M.query_tabs = {}
	M.active_tab = 0
end

return M
