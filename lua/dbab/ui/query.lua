local executor = require("dbab.core.executor")
local connection = require("dbab.core.connection")
local parser = require("dbab.utils.parser")
local storage = require("dbab.core.storage")
local query_history = require("dbab.core.history")

local function get_history_ui()
	return require("dbab.ui.history")
end

local M = {}

local workbench

function M.setup(workbench_ref)
	workbench = workbench_ref
end

---@type string[]
M.history = {}

---@type number
M.history_index = 0

---@param buf number
---@param callback? fun(success: boolean)
function M.save_query_by_buf(buf, callback)
	local tab = nil
	for _, t in ipairs(workbench.query_tabs) do
		if t.buf == buf then
			tab = t
			break
		end
	end
	if not tab then
		if callback then
			callback(false)
		end
		return
	end

	local conn_name = tab.conn_name or connection.get_active_name()
	if not conn_name then
		vim.notify("[dbab] No connection for query", vim.log.levels.WARN)
		if callback then
			callback(false)
		end
		return
	end

	local lines = vim.api.nvim_buf_get_lines(tab.buf, 0, -1, false)
	local content = table.concat(lines, "\n")

	local function do_save(name)
		local ok, err = storage.save_query(conn_name, name, content)
		if ok then
			tab.name = name
			tab.modified = false
			tab.is_saved = true
			workbench.refresh_tabbar()
			require("dbab.ui.sidebar").refresh()
			vim.notify("[dbab] Saved: " .. name, vim.log.levels.INFO)
			if callback then
				callback(true)
			end
		else
			vim.notify("[dbab] Save failed: " .. (err or "unknown"), vim.log.levels.ERROR)
			if callback then
				callback(false)
			end
		end
	end

	if tab.is_saved then
		do_save(tab.name)
	else
		vim.schedule(function()
			vim.ui.input({
				prompt = "Query name: ",
				default = tab.name:match("^query%-") and "" or tab.name,
			}, function(input)
				if input and input ~= "" then
					if storage.query_exists(conn_name, input) then
						vim.ui.select({ "Overwrite", "Cancel" }, {
							prompt = "Query '" .. input .. "' already exists",
						}, function(choice)
							if choice == "Overwrite" then
								do_save(input)
							else
								if callback then
									callback(false)
								end
							end
						end)
					else
						do_save(input)
					end
				else
					if callback then
						callback(false)
					end
				end
			end)
		end)
	end
end

---@param callback? fun(success: boolean)
function M.save_current_query(callback)
	local tab = workbench.get_active_tab()
	if not tab then
		vim.notify("[dbab] No active query tab", vim.log.levels.WARN)
		if callback then
			callback(false)
		end
		return
	end
	M.save_query_by_buf(tab.buf, callback)
end

---@param query_name string
---@param content string
---@param conn_name string
function M.open_saved_query(query_name, content, conn_name)
	if not workbench.tab_nr or not vim.api.nvim_tabpage_is_valid(workbench.tab_nr) then
		workbench.open()
	end

	for i, tab in ipairs(workbench.query_tabs) do
		if tab.name == query_name and tab.conn_name == conn_name and tab.is_saved then
			workbench.switch_tab(i)
			if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
				vim.api.nvim_set_current_win(workbench.editor_win)
			end
			return
		end
	end

	workbench.create_new_tab(query_name, content, conn_name, true)

	if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
		vim.api.nvim_set_current_win(workbench.editor_win)
	end
end

function M.execute_query()
	if not workbench.editor_buf or not vim.api.nvim_buf_is_valid(workbench.editor_buf) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(workbench.editor_buf, 0, -1, false)
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

	if workbench.history_win and vim.api.nvim_win_is_valid(workbench.history_win) then
		get_history_ui().render()
	end

	local result_mod = require("dbab.ui.result")
	result_mod.last_query = query
	result_mod.last_duration = elapsed
	result_mod.last_conn_name = connection.get_active_name()
	result_mod.last_timestamp = os.time()
	result_mod.show_result(result, elapsed)
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

M.delete_existing_buf = delete_existing_buf

function M.cleanup()
	M.history = {}
	M.history_index = 0
end

return M
