local config = require("dbab.config")

local M = {}

local ns = vim.api.nvim_create_namespace("dbab_help")

---@param key string|string[]
---@return string
local function format_key(key)
	if type(key) == "table" then
		return table.concat(key, " / ")
	end
	return key
end

---@class HelpEntry
---@field key string
---@field label string
---@field category string

---@param title string
---@param sections table<string, HelpEntry[]>
local function show_float(title, sections)
	local lines = {}
	local highlights = {}
	local max_key_len = 0

	for _, entries in pairs(sections) do
		for _, entry in ipairs(entries) do
			local klen = vim.fn.strdisplaywidth(entry.key)
			if klen > max_key_len then
				max_key_len = klen
			end
		end
	end

	local section_order = { "Actions", "Navigation", "Global" }

	for _, section_name in ipairs(section_order) do
		local entries = sections[section_name]
		if entries and #entries > 0 then
			if #lines > 0 then
				table.insert(lines, "")
			end
			table.insert(lines, "  " .. section_name)
			table.insert(highlights, { line = #lines - 1, col = 2, len = #section_name, hl = "DbabHistoryHeader" })

			for _, entry in ipairs(entries) do
				local klen = vim.fn.strdisplaywidth(entry.key)
				local padding = string.rep(" ", max_key_len - klen + 3)
				local line = "    " .. entry.key .. padding .. entry.label
				table.insert(lines, line)
				table.insert(highlights, { line = #lines - 1, col = 4, len = #entry.key, hl = "DbabKey" })
			end
		end
	end

	table.insert(lines, "")
	table.insert(lines, "  Press ? or q to close")
	table.insert(highlights, { line = #lines - 1, col = 2, len = 22, hl = "Comment" })

	local width = 0
	for _, line in ipairs(lines) do
		local w = vim.fn.strdisplaywidth(line)
		if w > width then
			width = w
		end
	end
	width = width + 4

	local height = #lines
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	for _, hl in ipairs(highlights) do
		local line_len = #lines[hl.line + 1]
		local end_col = math.min(hl.col + hl.len, line_len)
		if hl.col < line_len then
			vim.api.nvim_buf_set_extmark(buf, ns, hl.line, hl.col, {
				end_col = end_col,
				hl_group = hl.hl,
			})
		end
	end

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " Help ",
		title_pos = "center",
	})

	vim.wo[win].cursorline = false
	vim.wo[win].wrap = false

	local close = function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
	vim.keymap.set("n", "?", close, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
end

---@param keymaps table
---@param action string
---@param label string
---@param category string
---@param entries HelpEntry[]
local function add_entry(keymaps, action, label, category, entries)
	local key = keymaps[action]
	if key then
		table.insert(entries, { key = format_key(key), label = label, category = category })
	end
end

---@param entries HelpEntry[]
---@return table<string, HelpEntry[]>
local function group_by_category(entries)
	local grouped = {}
	for _, entry in ipairs(entries) do
		if not grouped[entry.category] then
			grouped[entry.category] = {}
		end
		table.insert(grouped[entry.category], entry)
	end
	return grouped
end

function M.show_sidebar()
	local cfg = config.get()
	local km = cfg.keymaps.sidebar
	local entries = {}

	add_entry(km, "toggle_expand", "Toggle expand", "Actions", entries)
	add_entry(km, "refresh", "Refresh", "Actions", entries)
	add_entry(km, "new_query", "New query", "Actions", entries)
	add_entry(km, "rename", "Rename query", "Actions", entries)
	add_entry(km, "delete", "Delete", "Actions", entries)
	add_entry(km, "insert_template", "Insert SELECT query", "Actions", entries)
	add_entry(km, "copy_name", "Copy name", "Actions", entries)
	add_entry(km, "copy_query", "Copy query content", "Actions", entries)
	add_entry(km, "paste_query", "Paste as new query", "Actions", entries)

	add_entry(km, "to_editor", "Go to editor", "Navigation", entries)
	add_entry(km, "to_history", "Go to history", "Navigation", entries)

	table.insert(entries, { key = format_key(cfg.keymaps.close), label = "Close dbab", category = "Global" })

	show_float("Sidebar", group_by_category(entries))
end

function M.show_editor()
	local cfg = config.get()
	local km = cfg.keymaps.editor
	local entries = {}

	table.insert(entries, { key = format_key(cfg.keymaps.execute), label = "Execute query", category = "Actions" })
	add_entry(km, "execute_insert", "Execute (insert mode)", "Actions", entries)
	add_entry(km, "execute_leader", "Execute (leader)", "Actions", entries)
	add_entry(km, "save", "Save query", "Actions", entries)
	add_entry(km, "next_tab", "Next tab", "Actions", entries)
	add_entry(km, "prev_tab", "Previous tab", "Actions", entries)
	add_entry(km, "close_tab", "Close tab", "Actions", entries)

	add_entry(km, "to_result", "Go to result", "Navigation", entries)
	add_entry(km, "to_sidebar", "Go to sidebar", "Navigation", entries)

	table.insert(entries, { key = format_key(cfg.keymaps.close), label = "Close dbab", category = "Global" })

	show_float("Editor", group_by_category(entries))
end

function M.show_history()
	local cfg = config.get()
	local km = cfg.keymaps.history
	local entries = {}

	add_entry(km, "select", "Open in editor", "Actions", entries)
	add_entry(km, "execute", "Re-execute", "Actions", entries)
	add_entry(km, "copy", "Copy query", "Actions", entries)
	add_entry(km, "delete", "Delete entry", "Actions", entries)
	add_entry(km, "clear", "Clear all", "Actions", entries)

	add_entry(km, "to_sidebar", "Go to sidebar", "Navigation", entries)
	add_entry(km, "to_result", "Go to result", "Navigation", entries)

	table.insert(entries, { key = format_key(cfg.keymaps.close), label = "Close dbab", category = "Global" })

	show_float("History", group_by_category(entries))
end

function M.show_result()
	local cfg = config.get()
	local km = cfg.keymaps.result
	local entries = {}

	add_entry(km, "yank_row", "Yank row as JSON", "Actions", entries)
	add_entry(km, "yank_all", "Yank all as JSON", "Actions", entries)

	add_entry(km, "to_sidebar", "Go to sidebar", "Navigation", entries)
	add_entry(km, "to_editor", "Go to editor", "Navigation", entries)

	table.insert(entries, { key = format_key(cfg.keymaps.close), label = "Close dbab", category = "Global" })

	show_float("Result", group_by_category(entries))
end

return M
