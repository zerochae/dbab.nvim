local connection = require "dbab.core.connection"
local schema = require "dbab.core.schema"
local storage = require "dbab.core.storage"
local workbench = require "dbab.ui.workbench"
local config = require "dbab.config"
local icons = require "dbab.ui.icons"

local M = {}

---@type table<string, boolean>
M.loading_names = {}

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

local db_hl_map = {
  postgres = "DbabIconPostgres",
  mysql = "DbabIconMysql",
  mariadb = "DbabIconMariadb",
  sqlite = "DbabIconSqlite",
  redis = "DbabIconRedis",
  mongodb = "DbabIconMongodb",
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
  if padding < 1 then
    padding = 1
  end
  return text .. string.rep(" ", padding) .. suffix
end

---@return string[]
local function render_tree()
  local lines = {}
  local sidebar_width = 30

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

    local sidebar_cfg = config.get().sidebar
    local resolved_url = connection.resolve_url(conn.url)
    local db_type = connection.parse_type(resolved_url)
    local conn_icon = sidebar_cfg.use_brand_icon and icons.db(db_type) or icons.db_default
    local conn_label = sidebar_cfg.show_brand_name and (" [" .. db_type .. "] ") or " "
    local conn_text = conn_icon .. conn_label .. conn.name
    local conn_status
    if M.loading_names[conn.name] then
      conn_status = icons.loading .. " loading"
    elseif is_active or connection.is_connected(conn.name) then
      conn_status = icons.connected .. " connected"
    else
      conn_status = icons.idle .. " idle"
    end
    table.insert(lines, pad_right(conn_text, sidebar_width - #conn_status - 1, conn_status))
    table.insert(M.nodes, {
      type = "connection",
      name = conn.name,
      expanded = is_expanded,
      depth = 0,
      ---@diagnostic disable-next-line: undefined-field
      db_type = db_type,
    })

    local conn_url = connection.resolve_url(conn.url)

    if is_expanded and conn_url then
      local open_tabs = workbench.query_tabs or {}
      local unsaved_buffers = {}
      local open_saved_map = {}
      for idx, tab in ipairs(open_tabs) do
        if tab.conn_name == conn.name then
          if tab.is_saved then
            open_saved_map[tab.name] = { tab_index = idx, modified = tab.modified }
          else
            table.insert(unsaved_buffers, { tab = tab, tab_index = idx })
          end
        end
      end

      local saved_queries = storage.list_queries(conn.name)

      -- Buffers folder
      local buffers_key = conn.name .. ".buffers"
      local buffers_expanded = M.expanded[buffers_key]
      local buffers_text = indent(1) .. icons.open_buffer .. " buffers"
      local buffers_suffix = "(" .. #unsaved_buffers .. ")"
      table.insert(lines, pad_right(buffers_text, sidebar_width - #buffers_suffix - 1, buffers_suffix))
      table.insert(M.nodes, {
        type = "buffers",
        name = "buffers",
        expanded = buffers_expanded,
        depth = 1,
        parent = conn.name,
      })

      if buffers_expanded then
        table.insert(lines, indent(2) .. icons.new_action .. " new")
        table.insert(M.nodes, {
          type = "new_query_action",
          name = "new",
          expanded = false,
          depth = 2,
          parent = conn.name,
        })

        for _, entry in ipairs(unsaved_buffers) do
          table.insert(lines, indent(2) .. icons.open_buffer .. " " .. entry.tab.name)
          table.insert(M.nodes, {
            type = "open_buffer",
            name = entry.tab.name,
            expanded = false,
            depth = 2,
            parent = conn.name,
            tab_index = entry.tab_index,
          })
        end
      end

      -- Saved queries folder
      local saved_key = conn.name .. ".saved"
      local saved_expanded = M.expanded[saved_key]
      local saved_text = indent(1) .. icons.saved_queries .. " saved queries"
      local saved_suffix = "(" .. #saved_queries .. ")"
      table.insert(lines, pad_right(saved_text, sidebar_width - #saved_suffix - 1, saved_suffix))
      table.insert(M.nodes, {
        type = "saved_queries",
        name = "saved queries",
        expanded = saved_expanded,
        depth = 1,
        parent = conn.name,
      })

      if saved_expanded then
        for _, query in ipairs(saved_queries) do
          local open_info = open_saved_map[query.name]
          local qi = (open_info and open_info.modified) and icons.query_modified or icons.query_file
          table.insert(lines, indent(2) .. qi .. " " .. query.name)
          table.insert(M.nodes, {
            type = "saved_query",
            name = query.name,
            expanded = false,
            depth = 2,
            parent = conn.name,
            query_path = query.path,
            tab_index = open_info and open_info.tab_index or nil,
          })
        end
      end

      -- Schema/table content
      do
        local schema_db_type = connection.parse_type(conn_url)
        local db_schemas = schema.get_schemas(conn_url)

        if schema_db_type == "mysql" or schema_db_type == "sqlite" then
          local tables_key = conn.name .. ".tables"
          local tables_expanded = M.expanded[tables_key]
          local all_tables = {}
          local total_count = 0

          if #db_schemas > 0 then
            if tables_expanded then
              all_tables = schema.get_tables(conn_url, db_schemas[1].name)
              total_count = #all_tables
            else
              total_count = db_schemas[1].table_count
            end
          end

          local tables_text = indent(1) .. icons.tables .. " tables"
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
              local type_icon = tbl.type == "view" and icons.view or icons.tbl

              table.insert(lines, indent(2) .. type_icon .. " " .. tbl.name)
              table.insert(M.nodes, {
                type = tbl.type,
                name = tbl.name,
                expanded = tbl_expanded,
                depth = 2,
                parent = conn.name,
                schema = nil,
              })

              if tbl_expanded then
                local columns = schema.get_columns(conn_url, tbl.name)
                for _, col in ipairs(columns) do
                  local col_icon = col.is_primary and icons.column_pk or icons.column
                  local type_hint = col.data_type and (" : " .. col.data_type) or ""

                  table.insert(lines, indent(3) .. col_icon .. " " .. col.name .. type_hint)
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
          local schemas_key = conn.name .. ".schemas"
          local schemas_expanded = M.expanded[schemas_key]

          local schemas_text = indent(1) .. icons.schemas .. " schemas"
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
              local tables = schema_expanded and schema.get_tables(conn_url, sch.name) or {}
              local table_count = schema_expanded and #tables or sch.table_count

              local schema_text = indent(2) .. icons.schema_node .. " " .. sch.name
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
                  local type_icon = tbl.type == "view" and icons.view or icons.tbl

                  table.insert(lines, indent(3) .. type_icon .. " " .. tbl.name)
                  table.insert(M.nodes, {
                    type = tbl.type,
                    name = tbl.name,
                    expanded = tbl_expanded,
                    depth = 3,
                    parent = conn.name,
                    schema = sch.name,
                  })

                  if tbl_expanded then
                    local columns = schema.get_columns(conn_url, tbl.name)
                    for _, col in ipairs(columns) do
                      local col_icon = col.is_primary and icons.column_pk or icons.column
                      local type_hint = col.data_type and (" : " .. col.data_type) or ""

                      table.insert(lines, indent(4) .. col_icon .. " " .. col.name .. type_hint)
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
        end
      end
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

  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_set_option(M.win, "winbar", "%#DbabHistoryHeader#" .. icons.header .. " Explorer%*")
  end

  M.apply_highlights()
end

local all_glyphs = {
  icons.postgres, icons.mysql, icons.sqlite, icons.db_default,
  icons.open_buffer, icons.saved_queries, icons.new_action,
  icons.query_file, icons.query_modified,
  icons.schemas, icons.schema_node, icons.tables, icons.tbl, icons.view,
  icons.column_pk, icons.column, icons.header,
}

---@param line string
---@return number byte offset where icon starts
local function find_icon_start(line)
  for _, icon in ipairs(all_glyphs) do
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

  local ns = vim.api.nvim_create_namespace "dbab_sidebar"
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)

  for i, line in ipairs(lines) do
    local line_num = i - 1
    local node = M.nodes[i]
    if not node then
      goto continue
    end

    local icon_start = find_icon_start(line)
    local icon_len = 0
    for _, glyph in ipairs(all_glyphs) do
      local pos = line:find(glyph, 1, true)
      if pos and pos - 1 == icon_start then
        icon_len = #glyph
        break
      end
    end
    local text_start = icon_start + icon_len + 1

    local status_start = line:find(icons.connected, 1, true) or line:find(icons.idle, 1, true)
    local loading_start = line:find(icons.loading, 1, true)

    if node.type == "connection" then
      local use_brand = config.get().sidebar.use_brand_color
      local db_hl = use_brand and db_hl_map[node.db_type] or nil
      local default_hl = "DbabIconDb"
      local tag_end = line:find("] ", 1, true)
      local name_start = tag_end and (tag_end + 1) or text_start

      local active_hl = db_hl or default_hl
      local idle_hl = db_hl or default_hl

      if line:find(icons.connected, 1, true) then
        vim.api.nvim_buf_add_highlight(M.buf, ns, active_hl, line_num, icon_start, name_start)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, name_start, status_start and status_start - 2 or -1)
        if status_start then
          vim.api.nvim_buf_add_highlight(M.buf, ns, active_hl, line_num, status_start - 1, status_start + #icons.connected - 1)
          vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, status_start + #icons.connected, -1)
        end
      elseif loading_start then
        vim.api.nvim_buf_add_highlight(M.buf, ns, active_hl, line_num, icon_start, name_start)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, name_start, loading_start - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "WarningMsg", line_num, loading_start - 1, -1)
      elseif line:find(icons.idle, 1, true) then
        vim.api.nvim_buf_add_highlight(M.buf, ns, idle_hl, line_num, icon_start, name_start)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, name_start, status_start and status_start - 2 or -1)
        if status_start then
          vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, status_start - 1, -1)
        end
      end
    elseif node.type == "buffers" or node.type == "saved_queries" then
      local folder_hl = node.type == "buffers" and "DbabSidebarIconNewQuery" or "DbabSidebarIconColumn"
      vim.api.nvim_buf_add_highlight(M.buf, ns, folder_hl, line_num, icon_start, icon_start + icon_len)
      local count_pos = line:find "%(%d+%)"
      if count_pos then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, count_pos - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, count_pos - 1, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif node.type == "new_query_action" then
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconNewQuery", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
    elseif node.type == "open_buffer" then
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconNewQuery", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
    elseif node.type == "saved_query" then
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconColumn", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
    elseif node.type == "schemas" or node.type == "tables" then
      local folder_hl = node.type == "schemas" and "DbabSidebarIconSchemas" or "DbabSidebarIconTable"
      vim.api.nvim_buf_add_highlight(M.buf, ns, folder_hl, line_num, icon_start, icon_start + icon_len)
      local count_pos = line:find "%(%d+%)"
      if count_pos then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, count_pos - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, count_pos - 1, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif node.type == "schema" then
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconSchema", line_num, icon_start, icon_start + icon_len)
      local count_pos = line:find "%(%d+%)"
      if count_pos then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, count_pos - 2)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, count_pos - 1, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    elseif node.type == "table" or node.type == "view" then
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarIconTable", line_num, icon_start, icon_start + icon_len)
      vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
    elseif node.type == "column" then
      local col_hl = node.is_primary and "DbabSidebarIconPK" or "DbabSidebarIconColumn"
      vim.api.nvim_buf_add_highlight(M.buf, ns, col_hl, line_num, icon_start, icon_start + icon_len)
      local col_end = line:find " : "
      if col_end then
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, col_end - 1)
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarType", line_num, col_end + 2, -1)
      else
        vim.api.nvim_buf_add_highlight(M.buf, ns, "DbabSidebarText", line_num, text_start, -1)
      end
    end

    ::continue::
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
      M.loading_names[node.name] = true
      connection.set_active(node.name)
      local active_tab = workbench.get_active_tab()
      if active_tab then
        active_tab.conn_name = node.name
      end
      for _, tab in ipairs(workbench.query_tabs) do
        if tab.conn_name == "no connection" then
          tab.conn_name = node.name
        end
      end
      M.refresh()
      workbench.refresh_history()

      local url = connection.get_active_url()
      if url then
        schema.get_schemas_async(url, function(schemas, err)
          if err then
            vim.notify("[dbab] Schema load error: " .. err, vim.log.levels.ERROR)
            M.loading_names[node.name] = nil
            M.refresh()
            return
          end

          local pending = #schemas
          if pending == 0 then
            M.loading_names[node.name] = nil
            M.expanded[node.name] = true
            M.expanded[node.name .. ".buffers"] = true
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
                M.loading_names[node.name] = nil
                M.expanded[node.name] = true
                M.expanded[node.name .. ".buffers"] = true
                M.expanded[node.name .. ".tables"] = true
                M.refresh()
                workbench.refresh_history()
                vim.notify("[dbab] Connected to: " .. node.name, vim.log.levels.INFO)
              end
            end)
          end
        end)
      else
        M.loading_names[node.name] = nil
        M.refresh()
      end
      return
    end
  elseif node.type == "buffers" then
    local key = node.parent .. ".buffers"
    M.expanded[key] = not M.expanded[key]
  elseif node.type == "saved_queries" then
    local key = node.parent .. ".saved"
    M.expanded[key] = not M.expanded[key]
  elseif node.type == "new_query_action" then
    M.open_new_query(node.parent)
    return
  elseif node.type == "open_buffer" then
    if node.tab_index then
      workbench.switch_tab(node.tab_index)
      if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
        vim.api.nvim_set_current_win(workbench.editor_win)
      end
    end
    return
  elseif node.type == "saved_query" then
    if node.tab_index then
      workbench.switch_tab(node.tab_index)
      if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
        vim.api.nvim_set_current_win(workbench.editor_win)
      end
    else
      M.open_saved_query(node.parent, node.name)
    end
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
    local key
    if node.schema then
      key = node.parent .. "." .. node.schema .. "." .. node.name
    else
      key = node.parent .. "." .. node.name
    end
    M.expanded[key] = not M.expanded[key]
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
  if conn_name ~= connection.get_active_name() then
    connection.set_active(conn_name)
  end

  workbench.open_editor()
end

---@param conn_name string
---@param query_name string
function M.open_saved_query(conn_name, query_name)
  if conn_name ~= connection.get_active_name() then
    connection.set_active(conn_name)
  end

  local content, err = storage.load_query(conn_name, query_name)
  if not content then
    vim.notify("[dbab] Failed to load query: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

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

  local function map(keys, func)
    if type(keys) == "table" then
      for _, key in ipairs(keys) do
        vim.keymap.set("n", key, func, opts)
      end
    else
      vim.keymap.set("n", keys, func, opts)
    end
  end

  map(keymaps.toggle_expand, function()
    M.toggle_node()
  end)

  map(keymaps.refresh, function()
    M.refresh()
  end)

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

  map(keymaps.new_query, function()
    local conn_name = connection.get_active_name()
    if conn_name then
      M.open_new_query(conn_name)
    else
      vim.notify("[dbab] No active connection", vim.log.levels.WARN)
    end
  end)

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

  map(keymaps.insert_template, function()
    local query = M.insert_table_query()
    if query then
      workbench.open_editor_with_query(query)
    end
  end)

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

  vim.keymap.set("n", config.get().keymaps.close, function()
    M.close()
  end, opts)

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

  map(keymaps.to_editor, function()
    if workbench.editor_win and vim.api.nvim_win_is_valid(workbench.editor_win) then
      vim.api.nvim_set_current_win(workbench.editor_win)
    end
  end)

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
  M.loading_names = {}
end

return M
