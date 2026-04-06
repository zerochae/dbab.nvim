local config = require("dbab.config")

local M = {}

local workbench

function M.setup(workbench_ref)
	workbench = workbench_ref
end

function M.setup_result_keymaps()
	if not workbench.result_buf then
		return
	end

	local result_opts = { noremap = true, silent = true, buffer = workbench.result_buf }
	local keymaps = config.get().keymaps.result

	vim.keymap.set("n", keymaps.to_sidebar, function()
		if workbench.history_win and vim.api.nvim_win_is_valid(workbench.history_win) then
			vim.api.nvim_set_current_win(workbench.history_win)
		elseif workbench.sidebar_win and vim.api.nvim_win_is_valid(workbench.sidebar_win) then
			vim.api.nvim_set_current_win(workbench.sidebar_win)
		end
	end, result_opts)

	vim.keymap.set("n", keymaps.to_editor, function()
		if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
			vim.api.nvim_set_current_win(workbench.editor_win)
		end
	end, result_opts)

	vim.keymap.set("n", keymaps.yank_row, function()
		workbench.yank_current_row()
	end, result_opts)

	vim.keymap.set("n", keymaps.yank_all, function()
		workbench.yank_all_rows()
	end, result_opts)

	vim.keymap.set("n", config.get().keymaps.close, function()
		workbench.close()
	end, result_opts)
end

---@param buf number
function M.setup_editor_keymaps(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local opts = { noremap = true, silent = true, buffer = buf }
	local keymaps = config.get().keymaps.editor

	vim.keymap.set("n", config.get().keymaps.execute, function()
		workbench.execute_query()
	end, opts)

	vim.keymap.set("i", keymaps.execute_insert, function()
		workbench.execute_query()
	end, opts)

	vim.keymap.set("n", keymaps.execute_leader, function()
		workbench.execute_query()
	end, opts)

	vim.keymap.set("n", keymaps.save, function()
		workbench.save_current_query()
	end, opts)

	vim.keymap.set("i", keymaps.save, function()
		vim.cmd("stopinsert")
		workbench.save_current_query()
	end, opts)

	vim.keymap.set("n", keymaps.next_tab, function()
		workbench.next_tab()
	end, opts)

	vim.keymap.set("n", keymaps.prev_tab, function()
		workbench.prev_tab()
	end, opts)

	vim.keymap.set("n", keymaps.close_tab, function()
		workbench.close_tab()
	end, opts)

	vim.keymap.set("n", keymaps.to_result, function()
		if workbench.result_win and vim.api.nvim_win_is_valid(workbench.result_win) then
			vim.api.nvim_set_current_win(workbench.result_win)
		elseif workbench.sidebar_win and vim.api.nvim_win_is_valid(workbench.sidebar_win) then
			vim.api.nvim_set_current_win(workbench.sidebar_win)
		end
	end, opts)

	vim.keymap.set("n", keymaps.to_sidebar, function()
		if workbench.sidebar_win and vim.api.nvim_win_is_valid(workbench.sidebar_win) then
			vim.api.nvim_set_current_win(workbench.sidebar_win)
		end
	end, opts)

	vim.keymap.set("n", config.get().keymaps.close, function()
		workbench.close()
	end, opts)
end

function M.setup_keymaps()
	if workbench.editor_buf then
		M.setup_editor_keymaps(workbench.editor_buf)
	end
end

return M
