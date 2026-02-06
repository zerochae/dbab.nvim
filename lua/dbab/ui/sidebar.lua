local connection = require("dbab.core.connection")
local schema = require("dbab.core.schema")
local storage = require("dbab.core.storage")
local workbench = require("dbab.ui.workbench")
local config = require("dbab.config")

local M = {}

---@type boolean
M.is_loading = false

---@type {name: string, conn_name: string, content: string}|nil
M.clipboard = nil

---@type number|nil
M.buf = nil

---@type number|nil
M.win = nil

--- See lua/dbab/types.lua for type definitions (Dbab.SidebarNode)

---@type Dbab.SidebarNode[]
M.nodes = {}

---@type table<string, boolean>
M.expanded = {}

-- dbab style icons
local icons = {
  header = "󰙅 ",
  connection = "󰆼 ",
  queries = "󰷉 ",
  query_file = "󰈙 ",
  query_modified = "󰏪 ",
  new_query = "󰝒 ",
  schemas = "󰒋 ",
  schema = "󰙅 ",
  tables = "󰓱 ",
  table = "󰓫 ",
  view = "󰈈 ",
  column = "󰠵 ",
  column_pk = "󰌋 ",
}

-- Status indicators
local status = {
  connected = "✓ connected",
  loading = "◐ loading",
  idle = "○ idle",
}

---@param depth number
---@return string
local function indent(depth)
  return string.rep("  ", depth)
end

---@param text string
---@param width number
---@param suffix string
---@return string
local function pad_right(text, width, suffix)
  local display_width = vim.fn.strdisplaywidth(text)
  local padding = width - display_width
  if padding < 1 then padding = 1 end
  return text .. string.rep(" ", padding) .. suffix
end

---@return string[]
local function render_tree()
  local lines = {}
  local url = connection.get_active_url()
  local sidebar_width = 30

  -- Header is now in winbar, not in buffer

  local connections = connection.list_connections()
  if #connections == 0 then
    table.insert(lines, "No connections configured")
    table.insert(lines, "Press 'a' to add connection")
    M.nodes = {}
    return lines
  end

  M.nodes = {}

  for _, conn in ipairs(connections) do
    local is_active = conn.name == connection.get_active_name()
    local is_expanded = M.expanded[conn.name]

    -- Connection line with status
    local conn_text = icons.connection .. conn.name
    local conn_status
    if is_active and M.is_loading then
      conn_status = status.loading
    elseif is_active then
      conn_status = status.connected
    else
      conn_status = status.idle
    end
    table.insert(lines, pad_right(conn_text, sidebar_width - #conn_status - 1, conn_status))
    table.insert(M.nodes, {
      type = "connection",
      name = conn.name,
      expanded = is_expanded,
      depth = 0,
    })

    -- Show content if expanded and active (but not while loading)
    if is_expanded and is_active and url and not M.is_loading then
      -- Queries folder (merged: new query + saved queries)
      local queries_key = conn.name .. ".queries"
      local queries_expanded = M.expanded[queries_key]
      local open_tabs = workbench.query_tabs or {}
      local saved_queries = storage.list_queries(conn.name)
      local saved_count = #saved_queries

      local queries_text = indent(1) .. icons.queries .. "queries"
      local queries_suffix = "(" .. saved_count .. ")"
      table.insert(lines, pad_right(queries_text, sidebar_width - #queries_suffix - 1, queries_suffix))
      table.insert(M.nodes, {
        type = "queries",
        name = "queries",
        expanded = queries_expanded,
        depth = 1,
        parent = conn.name,
      })

      if queries_expanded then
        -- Always show "new query" button first
        table.insert(lines, indent(1) .. "  " .. icons.new_query .. "new query")
        table.insert(M.nodes, {
          type = "new_query_action",
          name = "new query",
          expanded = false,
          depth = 1,
          parent = conn.name,
        })

        -- Show saved queries
        for _, query in ipairs(saved_queries) do
          -- Check if this saved query is currently open and/or modified
          local is_modified = false
          local is_query_active = false
          local tab_idx = nil
          for idx, tab in ipairs(open_tabs) do
            if tab.is_saved and tab.name == query.name then
              is_modified = tab.modified
              is_query_active = (idx == workbench.active_tab)
              tab_idx = idx
              break
            end
          end
          local active_marker = is_query_active and "▸ " or "  "
          local query_icon = is_modified and icons.query_modified or icons.query_file
          table.insert(lines, indent(1) .. active_marker .. query_icon .. query.name)
          table.insert(M.nodes, {
            type = "saved_query",
            name = query.name,
            expanded = false,
            depth = 1,
            parent = conn.name,
            query_path = query.path,
            tab_index = tab_idx,
          })
        end
      end

      -- Schema/table content
      do
        local db_type = connection.parse_type(url)
        local db_schemas = schema.get_schemas(url)

        if db_type == "mysql" or db_type == "sqlite" then
        -- MySQL/SQLite: Show "tables (N)" folder directly
        local tables_key = conn.name .. ".tables"
        local tables_expanded = M.expanded[tables_key]
        local all_tables = {}
        local total_count = 0

        -- Get tables from first schema (mysql uses db name, sqlite uses "main")
        if #db_schemas > 0 then
          if tables_expanded then
            all_tables = schema.get_tables(url, db_schemas[1].name)
            total_count = #all_tables
          else
            total_count = db_schemas[1].table_count
          end
        end

        -- tables folder
        local tables_text = indent(1) .. icons.tables .. "tables"
        local tables_suffix = "(" .. total_count .. ")"
        table.insert(lines, pad_right(tables_text, sidebar_width - #tables_suffix - 1, tables_suffix))
        table.insert(M.nodes, {
          type = "tables",
          name = "tables",
          expanded = tables_expanded,
          depth = 1,
          parent = conn.name,
        })

        if tables_expanded then
          for _, tbl in ipairs(all_tables) do
            local tbl_key = conn.name .. "." .. tbl.name
            local tbl_expanded = M.expanded[tbl_key]
            local type_icon = tbl.type == "view" and icons.view or icons.table

            table.insert(lines, indent(2) .. type_icon .. tbl.name)
            table.insert(M.nodes, {
              type = tbl.type,
              name = tbl.name,
              expanded = tbl_expanded,
              depth = 2,
              parent = conn.name,
              schema = nil, -- MySQL/SQLite: no schema prefix in key
            })

            if tbl_expanded then
              local columns = schema.get_columns(url, tbl.name)
              for _, col in ipairs(columns) do
                local col_icon = col.is_primary and icons.column_pk or icons.column
                local type_hint = col.data_type and (" : " .. col.data_type) or ""

                table.insert(lines, indent(3) .. col_icon .. col.name .. type_hint)
                table.insert(M.nodes, {
                  type = "column",
                  name = col.name,
                  expanded = false,
                  depth = 3,
                  data_type = col.data_type,
                  is_primary = col.is_primary,
                  parent = tbl.name,
                  schema = db_schemas[1] and db_schemas[1].name or "main",
                })
              end
            end
          end
        end
      else
        -- PostgreSQL: Show "schemas (N)" folder
        local schemas_key = conn.name .. ".schemas"
        local schemas_expanded = M.expanded[schemas_key]

        local schemas_text = indent(1) .. icons.schemas .. "schemas"
        local schemas_suffix = "(" .. #db_schemas .. ")"
        table.insert(lines, pad_right(schemas_text, sidebar_width - #schemas_suffix - 1, schemas_suffix))
        table.insert(M.nodes, {
          type = "schemas",
          name = "schemas",
          expanded = schemas_expanded,
          depth = 1,
          parent = conn.name,
        })

        if schemas_expanded then
          for _, sch in ipairs(db_schemas) do
            local schema_key = conn.name .. ".schema." .. sch.name
            local schema_expanded = M.expanded[schema_key]
            local tables = schema_expanded and schema.get_tables(url, sch.name) or {}
            local table_count = schema_expanded and #tables or sch.table_count

            -- Schema line with table count
            local schema_text = indent(2) .. icons.schema .. sch.name
            local schema_suffix = "(" .. table_count .. ")"
            table.insert(lines, pad_right(schema_text, sidebar_width - #schema_suffix - 1, schema_suffix))
            table.insert(M.nodes, {
              type = "schema",
              name = sch.name,
              expanded = schema_expanded,
              depth = 2,
              parent = conn.name,
            })

            if schema_expanded then
              for _, tbl in ipairs(tables) do
                local tbl_key = conn.name .. "." .. sch.name .. "." .. tbl.name
                local tbl_expanded = M.expanded[tbl_key]
                local type_icon = tbl.type == "view" and icons.view or icons.table

                table.insert(lines, indent(3) .. type_icon .. tbl.name)
                table.insert(M.nodes, {
                  type = tbl.type,
                  name = tbl.name,
                  expanded = tbl_expanded,
                  depth = 3,
                  parent = conn.name,
                  schema = sch.name,
                })

                if tbl_expanded then
                  local columns = schema.get_columns(url, tbl.name)
                  for _, col in ipairs(columns) do
                    local col_icon = col.is_primary and icons.column_pk or icons.column
                    local type_hint = col.data_type and (" : " .. col.data_type) or ""

                    table.insert(lines, indent(4) .. col_icon .. col.name .. type_hint)
                    table.insert(M.nodes, {
                      type = "column",
                      name = col.name,
                      expanded = false,
                      depth = 4,
                      data_type = col.data_type,
                      is_primary = col.is_primary,
                      parent = tbl.name,
                      schema = sch.name,
                    })
                  end
                end
              end
            end
          end
        end
      end -- end if db_type
      end -- end do block
    end
  end

  return lines
end

function M.refresh()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end

  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local lines = render_tree()
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)

  -- Set winbar header
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_set_option(M.win, "winbar", "%#DbabHistoryHeader#" .. icons.header .. "Explorer%*")
  end

  M.apply_highlights()
end

---@param line string
---@return number byte offset where icon starts
local function find_icon_start(line)
  local icon_patterns = { "󰆼", "󰓰", "󰷉", "󰈙", "󰒋", "󰓱", "󰙅", "󰓫", "󰈈", "󰠵", "󰌋" }
  for _, icon in ipairs(icon_patterns) do
    local pos = line:find(icon, 1, true)
    if pos then
      return pos - 1
    end
  end
  return 0
end

function M.apply_highlights()
  if not M.buf then
    return
  end

  local ns = vim.api.nvim_create_namespace("dbab_sidebar")
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
  local icon_len = 5 -- nerd font icon (4 bytes) + space

  for i, line in ipairs(lines) do
    local line_num = i - 1
    local icon_start = find_icon_start(line)
    local text_start = icon_start + icon_len

    -- Find status text position (right-aligned)
    local status_start = line:find("[✓○]")

    -- Connection with connected status
    if line:match("✓ connected") then
      -- Active connection: icon only colored, text is normal
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconActive", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, status_start and status_start - 2 or -1)
      if status_start then
        -- ✓ symbol gets active color, "connected" text gets muted
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconActive", line_num, status_start - 1, status_start + 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, status_start + 2, -1)
      end
    elseif line:match("◐ loading") then
      -- Loading connection: icon colored, loading status gets warning color
      local loading_start = line:find("◐")
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconActive", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, loading_start and loading_start - 2 or -1)
      if loading_start then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "WarningMsg", line_num, loading_start - 1, -1)
      end
    elseif line:match("○ idle") then
      -- Idle connection
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconConnection", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, status_start and status_start - 2 or -1)
      if status_start then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, status_start - 1, -1)
      end
    elseif line:match("󰓰") then
      -- Query note
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconNewQuery", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
    elseif line:match("󰷉") then
      -- Saved queries folder
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconNewQuery", line_num, icon_start, icon_start + icon_len)
      local count_pos = line:find("%(%d+%)")
      if count_pos then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, count_pos - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, count_pos - 1, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif line:match("󰈙") then
      -- Saved query file
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconColumn", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
    elseif line:match("󰒋") then
      -- schemas folder
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconSchemas", line_num, icon_start, icon_start + icon_len)
      local count_pos = line:find("%(%d+%)")
      if count_pos then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, count_pos - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, count_pos - 1, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif line:match("󰓱") then
      -- tables folder
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconTable", line_num, icon_start, icon_start + icon_len)
      local count_pos = line:find("%(%d+%)")
      if count_pos then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, count_pos - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, count_pos - 1, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif line:match("󰙅") then
      -- Schema with table count
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconSchema", line_num, icon_start, icon_start + icon_len)
      local count_pos = line:find("%(%d+%)")
      if count_pos then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, count_pos - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, count_pos - 1, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif line:match("󰓫") or line:match("󰈈") then
      -- Table/View
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconTable", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
    elseif line:match("󰌋") then
      -- Primary key column
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconPK", line_num, icon_start, icon_start + icon_len)
      local col_end = line:find(" : ")
      if col_end then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, col_end - 1)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, col_end + 2, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif line:match("󰠵") then
      -- Column
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconColumn", line_num, icon_start, icon_start + icon_len)
      local col_end = line:find(" : ")
      if col_end then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, col_end - 1)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, col_end + 2, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    end
  end
end

function M.toggle_node()
  if not M.buf or not M.win then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(M.win)
  local row = cursor[1]
  local node_idx = row

  if node_idx < 1 or node_idx > #M.nodes then
    return
  end

  local node = M.nodes[node_idx]

  if node.type == "connection" then
    M.expanded[node.name] = not M.expanded[node.name]
    if M.expanded[node.name] and node.name ~= connection.get_active_name() then
      -- Show loading state first
      M.is_loading = true
      connection.set_active(node.name)
      M.refresh() -- Show loading indicator immediately

      -- Load schema asynchronously (non-blocking)
      local url = connection.get_active_url()
      if url then
        schema.get_schemas_async(url, function(schemas, err)
          if err then
            vim.notify("[dbab] Schema load error: " .. err, vim.log.levels.ERROR)
            M.is_loading = false
            M.refresh()
            return
          end

          -- Pre-load tables for all schemas
          local pending = #schemas
          if pending == 0 then
            M.is_loading = false
            -- Auto-expand connection and tables folder
            M.expanded[node.name] = true
            M.expanded[node.name .. ".tables"] = true
            M.refresh()
            workbench.refresh_history()
            vim.notify("[dbab] Connected to: " .. node.name, vim.log.levels.INFO)
            return
          end

          for _, sch in ipairs(schemas) do
            schema.get_tables_async(url, sch.name, function(_, _)
              pending = pending - 1
              if pending <= 0 then
                M.is_loading = false
                -- Auto-expand connection and tables folder
                M.expanded[node.name] = true
                M.expanded[node.name .. ".tables"] = true
                M.refresh()
                workbench.refresh_history()
                vim.notify("[dbab] Connected to: " .. node.name, vim.log.levels.INFO)
              end
            end)
          end
        end)
      else
        M.is_loading = false
        M.refresh()
      end
      return -- Don't call refresh again at the end
    end
  elseif node.type == "queries" then
    -- Toggle expansion
    local key = node.parent .. ".queries"
    M.expanded[key] = not M.expanded[key]
  elseif node.type == "new_query_action" then
    -- Create new query
    M.open_new_query(node.parent)
    return
  elseif node.type == "open_buffer" then
    -- Switch to the tab
    if node.tab_index then
      workbench.switch_tab(node.tab_index)
      -- Focus editor window
      if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
        vim.api.nvim_set_current_win(workbench.editor_win)
      end
    end
    return
  elseif node.type == "saved_query" then
    -- Open saved query in editor
    M.open_saved_query(node.parent, node.name)
    return
  elseif node.type == "schemas" then
    local key = node.parent .. ".schemas"
    M.expanded[key] = not M.expanded[key]
  elseif node.type == "tables" then
    local key = node.parent .. ".tables"
    M.expanded[key] = not M.expanded[key]
  elseif node.type == "schema" then
    local key = node.parent .. ".schema." .. node.name
    M.expanded[key] = not M.expanded[key]
  elseif node.type == "table" or node.type == "view" then
    -- MySQL/SQLite: conn.tablename, PostgreSQL: conn.schema.tablename
    local key
    if node.schema then
      key = node.parent .. "." .. node.schema .. "." .. node.name
    else
      key = node.parent .. "." .. node.name
    end
    M.expanded[key] = not M.expanded[key]
    -- Debug: show what key is being toggled
    -- vim.notify("[dbab] Toggle table: " .. key .. " = " .. tostring(M.expanded[key]), vim.log.levels.INFO)
  elseif node.type == "column" then
    vim.fn.setreg("+", node.name)
    vim.fn.setreg('"', node.name)
    vim.notify("[dbab] Copied: " .. node.name, vim.log.levels.INFO)
    return
  end

  M.refresh()
end

---@param conn_name string
function M.open_new_query(conn_name)
  -- Set active connection if needed
  if conn_name ~= connection.get_active_name() then
    connection.set_active(conn_name)
  end

  -- Open workbench with editor
  workbench.open_editor()
end

---@param conn_name string
---@param query_name string
function M.open_saved_query(conn_name, query_name)
  -- Set active connection if needed
  if conn_name ~= connection.get_active_name() then
    connection.set_active(conn_name)
  end

  -- Load query content
  local content, err = storage.load_query(conn_name, query_name)
  if not content then
    vim.notify("[dbab] Failed to load query: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  -- Open workbench with the saved query
  workbench.open_saved_query(query_name, content, conn_name)
end

---@param conn_name string
---@param query_name string
function M.delete_saved_query(conn_name, query_name)
  local ok, err = storage.delete_query(conn_name, query_name)
  if ok then
    vim.notify("[dbab] Deleted query: " .. query_name, vim.log.levels.INFO)
    M.refresh()
  else
    vim.notify("[dbab] Failed to delete: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

function M.insert_table_query()
  if not M.buf or not M.win then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(M.win)
  local row = cursor[1]
  local node_idx = row

  if node_idx < 1 or node_idx > #M.nodes then
    return
  end

  local node = M.nodes[node_idx]

  if node.type == "table" or node.type == "view" then
    local schema_prefix = node.schema and node.schema ~= "public" and (node.schema .. ".") or ""
    local query = string.format('SELECT * FROM %s"%s" LIMIT 10;', schema_prefix, node.name)
    return query
  elseif node.type == "column" then
    return node.name
  end

  return nil
end

---@param buf number
---@param win number
function M.setup(buf, win)
  M.buf = buf
  M.win = win

  vim.api.nvim_buf_set_option(buf, "filetype", "dbab_sidebar")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "buflisted", false)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_name(buf, "[dbab] Explorer")

  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")
  vim.api.nvim_win_set_option(win, "foldcolumn", "0")
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "winfixwidth", true)

  M.setup_keymaps()
  M.refresh()
end

function M.setup_keymaps()
  if not M.buf then
    return
  end

  local opts = { noremap = true, silent = true, buffer = M.buf }
  local keymaps = config.get().keymaps.sidebar

  -- Helper for multiple keys
  local function map(keys, func)
    if type(keys) == "table" then
      for _, key in ipairs(keys) do
        vim.keymap.set("n", key, func, opts)
      end
    else
      vim.keymap.set("n", keys, func, opts)
    end
  end

  -- Toggle expand/collapse
  map(keymaps.toggle_expand, function()
    M.toggle_node()
  end)

  -- Refresh
  map(keymaps.refresh, function()
    M.refresh()
  end)

  -- Rename saved query
  map(keymaps.rename, function()
    local cursor = vim.api.nvim_win_get_cursor(M.win)
    local node_idx = cursor[1]
    if node_idx >= 1 and node_idx <= #M.nodes then
      local node = M.nodes[node_idx]
      if node.type == "saved_query" then
        vim.ui.input({
          prompt = "Rename to: ",
          default = node.name,
        }, function(new_name)
          if new_name and new_name ~= "" and new_name ~= node.name then
            local ok, err = storage.rename_query(node.parent, node.name, new_name)
            if ok then
              -- Update any open tab with this query
              for _, tab in ipairs(workbench.query_tabs or {}) do
                if tab.is_saved and tab.name == node.name and tab.conn_name == node.parent then
                  tab.name = new_name
                end
              end
              workbench.refresh_tabbar()
              M.refresh()
              vim.notify("[dbab] Renamed to: " .. new_name, vim.log.levels.INFO)
            else
              vim.notify("[dbab] Rename failed: " .. (err or "unknown"), vim.log.levels.ERROR)
            end
          end
        end)
      end
    end
  end)

  -- New query
  map(keymaps.new_query, function()
    local conn_name = connection.get_active_name()
    if conn_name then
      M.open_new_query(conn_name)
    else
      vim.notify("[dbab] No active connection", vim.log.levels.WARN)
    end
  end)

  -- Copy name
  map(keymaps.copy_name, function()
    local cursor = vim.api.nvim_win_get_cursor(M.win)
    local node_idx = cursor[1]
    if node_idx >= 1 and node_idx <= #M.nodes then
      local node = M.nodes[node_idx]
      if node.name then
        vim.fn.setreg("+", node.name)
        vim.fn.setreg('"', node.name)
        vim.notify("[dbab] Copied: " .. node.name, vim.log.levels.INFO)
      end
    end
  end)

  -- Insert table query
  map(keymaps.insert_template, function()
    local query = M.insert_table_query()
    if query then
      workbench.open_editor_with_query(query)
    end
  end)

  -- Delete saved query
  map(keymaps.delete, function()
    local cursor = vim.api.nvim_win_get_cursor(M.win)
    local node_idx = cursor[1]
    if node_idx >= 1 and node_idx <= #M.nodes then
      local node = M.nodes[node_idx]
      if node.type == "saved_query" then
        vim.ui.select({ "Yes", "No" }, {
          prompt = "Delete query '" .. node.name .. "'?",
        }, function(choice)
          if choice == "Yes" then
            storage.delete_query(node.parent, node.name)
            M.refresh()
          end
        end)
      end
    end
  end)

  -- Close
  vim.keymap.set("n", config.get().keymaps.close, function()
    M.close()
  end, opts)

  -- Copy saved query
  map(keymaps.copy_query, function()
    local cursor = vim.api.nvim_win_get_cursor(M.win)
    local node_idx = cursor[1]
    if node_idx >= 1 and node_idx <= #M.nodes then
      local node = M.nodes[node_idx]
      if node.type == "saved_query" then
        local content = storage.load_query(node.parent, node.name)
        if content then
          M.clipboard = {
            name = node.name,
            conn_name = node.parent,
            content = content,
          }
          vim.notify("[dbab] Copied: " .. node.name, vim.log.levels.INFO)
        end
      end
    end
  end)

  -- Paste saved query
  map(keymaps.paste_query, function()
    if not M.clipboard then
      vim.notify("[dbab] Nothing to paste", vim.log.levels.WARN)
      return
    end
    local conn_name = connection.get_active_name()
    if not conn_name then
      vim.notify("[dbab] No active connection", vim.log.levels.WARN)
      return
    end
    -- Generate unique name
    local base_name = M.clipboard.name
    local new_name = base_name .. "_copy"
    local counter = 1
    while storage.query_exists(conn_name, new_name) do
      counter = counter + 1
      new_name = base_name .. "_copy" .. counter
    end
    vim.ui.input({
      prompt = "Paste as: ",
      default = new_name,
    }, function(input)
      if input and input ~= "" then
        if storage.query_exists(conn_name, input) then
          vim.notify("[dbab] Query '" .. input .. "' already exists", vim.log.levels.ERROR)
          return
        end
        local ok, err = storage.save_query(conn_name, input, M.clipboard.content)
        if ok then
          M.refresh()
          vim.notify("[dbab] Pasted: " .. input, vim.log.levels.INFO)
        else
          vim.notify("[dbab] Paste failed: " .. (err or "unknown"), vim.log.levels.ERROR)
        end
      end
    end)
  end)

  -- Tab: To Editor
  map(keymaps.to_editor, function()
    if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
      vim.api.nvim_set_current_win(workbench.editor_win)
    end
  end)

  -- S-Tab: To History
  map(keymaps.to_history, function()
    if workbench.history_win and vim.api.nvim_win_is_valid(workbench.history_win) then
      vim.api.nvim_set_current_win(workbench.history_win)
    end
  end)
end

function M.cleanup()
  M.buf = nil
  M.win = nil
  M.nodes = {}
end

return M
