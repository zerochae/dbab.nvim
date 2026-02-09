---@meta
--- Dbab Type Definitions
--- This file contains all type definitions for the dbab.nvim plugin.

---============================================================================
--- Configuration Types
---============================================================================

---@class Dbab.Config
---@field connections Dbab.Connection[]
---@field ui Dbab.UIConfig
---@field keymaps Dbab.Keymaps
---@field schema Dbab.SchemaConfig
---@field history Dbab.HistoryConfig

---@class Dbab.Connection
---@field name string Connection display name
---@field url string Database connection URL (supports env vars like $DATABASE_URL)

---@alias Dbab.ResultStyle "table"|"json"|"raw"|"vertical"|"markdown"

---@class Dbab.UIConfig
---@field layout Dbab.Layout Declarative layout configuration
---@field grid Dbab.GridConfig
---@field sidebar Dbab.SidebarUIConfig
---@field history Dbab.HistoryUIConfig

---@class Dbab.SidebarUIConfig
---@field width number Width as percentage (0.1~1.0)

---@class Dbab.HistoryUIConfig
---@field width number Width as percentage (0.1~1.0)

---@alias Dbab.HeaderAlign "fit"|"full"

---@class Dbab.GridConfig
---@field max_width number Maximum grid width
---@field max_height number Maximum grid height
---@field show_line_number boolean Show line numbers in result grid
---@field header_align Dbab.HeaderAlign Winbar metadata alignment ("fit" = align to grid, "full" = align to window edge)
---@field style? Dbab.ResultStyle Result display style ("table" = table grid, "json" = JSON, "raw" = plain text, "vertical" = record per line, "markdown" = markdown table)

---@class Dbab.SchemaConfig
---@field show_system_schemas boolean Show system schemas (pg_catalog, information_schema)

---@alias Dbab.HistoryField "icon"|"time"|"dbname"|"query"|"duration"

---@alias Dbab.ShortHint "where"|"join"|"order"|"group"|"limit"

---@class Dbab.HistoryConfig
---@field max_entries number Maximum history entries (default 100)
---@field on_select "execute"|"load" Action when selecting history item
---@field persist boolean Whether to persist history to disk
---@field filter_by_connection boolean Filter history by current connection (default true)
---@field format? Dbab.HistoryField[] Fields to show and their order (nil = auto based on filter_by_connection)
---@field query_display "short"|"full"|"auto" How to display query ("short" = summary, "full" = full query with syntax highlight, "auto" = full if fits, else short)
---@field short_hints? Dbab.ShortHint[] Hints to show in short mode (nil = none, e.g., {"where", "join", "limit"})

---@class Dbab.Keymaps
---@field open string Keymap to open dbab
---@field execute string Keymap to execute query (Global)
---@field close string Keymap to close dbab (Global)
---@field sidebar Dbab.SidebarKeymaps
---@field history Dbab.HistoryKeymaps
---@field editor Dbab.EditorKeymaps
---@field result Dbab.ResultKeymaps

---@class Dbab.SidebarKeymaps
---@field toggle_expand string|string[] Toggle expand/collapse or open query
---@field refresh string Refresh sidebar
---@field rename string Rename saved query
---@field new_query string Create new query
---@field copy_name string Copy node name
---@field insert_template string Insert table query template
---@field delete string Delete saved query
---@field copy_query string Copy saved query content
---@field paste_query string Paste saved query
---@field to_editor string Move focus to editor
---@field to_history string Move focus to history

---@class Dbab.HistoryKeymaps
---@field select string Select entry (load or execute)
---@field execute string Re-execute query
---@field copy string Copy query text
---@field delete string Delete entry
---@field clear string Clear all history
---@field to_sidebar string Move focus to sidebar
---@field to_result string Move focus to result

---@class Dbab.EditorKeymaps
---@field execute_insert string Execute query in insert mode
---@field execute_leader string Execute query with leader
---@field save string Save current query
---@field next_tab string Next query tab
---@field prev_tab string Previous query tab
---@field close_tab string Close current tab
---@field to_result string Move focus to result
---@field to_sidebar string Move focus to sidebar

---@class Dbab.ResultKeymaps
---@field yank_row string Yank current row as JSON
---@field yank_all string Yank all rows as JSON
---@field to_sidebar string Move focus to sidebar
---@field to_editor string Move focus to editor

-- Aliases for backward compatibility
---@alias DbabConfig Dbab.Config
---@alias DbabConnection Dbab.Connection
---@alias DbabUIConfig Dbab.UIConfig
---@alias DbabGridConfig Dbab.GridConfig
---@alias DbabSchemaConfig Dbab.SchemaConfig
---@alias DbabHistoryConfig Dbab.HistoryConfig
---@alias DbabHistoryEntry Dbab.HistoryEntry
---@alias DbabKeymaps Dbab.Keymaps

---============================================================================
--- Database Schema Types
---============================================================================

---@class Dbab.Schema
---@field name string Schema name
---@field table_count number Number of tables in schema

---@class Dbab.Table
---@field name string Table name
---@field type "table"|"view" Table type

---@class Dbab.Column
---@field name string Column name
---@field data_type string SQL data type
---@field is_nullable boolean Whether column allows NULL
---@field is_primary boolean Whether column is primary key

-- Aliases for backward compatibility
---@alias DbabSchema Dbab.Schema
---@alias DbabTable Dbab.Table
---@alias DbabColumn Dbab.Column

---============================================================================
--- History Types
---============================================================================

---@class Dbab.HistoryEntry
---@field query string SQL query text
---@field timestamp number Unix timestamp
---@field conn_name string Connection name
---@field duration_ms? number Execution time in milliseconds
---@field row_count? number Number of rows returned

---============================================================================
--- Query Types
---============================================================================

---@class Dbab.QueryResult
---@field columns string[] Column names
---@field rows string[][] Row data (each row is array of cell values)
---@field row_count number Total number of rows
---@field raw string Raw query output

---@class Dbab.QueryTab
---@field buf number Buffer number
---@field name string Tab display name
---@field conn_name string Associated connection name
---@field modified boolean Whether buffer has unsaved changes
---@field is_saved boolean Whether query is saved to disk

-- Aliases for backward compatibility
---@alias DbabQueryResult Dbab.QueryResult
---@alias QueryTab Dbab.QueryTab

---============================================================================
--- UI Types
---============================================================================

---@alias Dbab.SidebarNodeType
---| "header"
---| "connection"
---| "queries"
---| "new_query_action"
---| "saved_query"
---| "schemas"
---| "schema"
---| "tables"
---| "table"
---| "view"
---| "column"

---@class Dbab.SidebarNode
---@field type Dbab.SidebarNodeType Node type
---@field name string Display name
---@field expanded boolean Whether node is expanded
---@field depth number Indentation depth
---@field data_type? string Column data type (for column nodes)
---@field is_primary? boolean Is primary key (for column nodes)
---@field parent? string Parent connection name
---@field schema? string Schema name (for table nodes)
---@field action? string Action to perform on select
---@field query_path? string Path to saved query file
---@field tab_index? number Index in query_tabs array

-- Aliases for backward compatibility
---@alias SidebarNode Dbab.SidebarNode
---@alias SidebarNodeType Dbab.SidebarNodeType

---@alias Dbab.DatabaseType "postgres"|"mysql"|"sqlite"|"unknown"

---============================================================================
--- Layout Types
---============================================================================

---@alias Dbab.LayoutComponent "sidebar"|"editor"|"history"|"grid"

---@alias Dbab.LayoutRow Dbab.LayoutComponent[]

---@alias Dbab.LayoutPreset "classic"|"wide"

---@alias Dbab.Layout Dbab.LayoutRow[]|Dbab.LayoutPreset

---============================================================================
--- Highlight Groups (documentation only)
---============================================================================

--- Result Grid:
---   DbabHeader, DbabRowOdd, DbabRowEven, DbabSeparator
--- Data Types:
---   DbabNull, DbabNumber, DbabString, DbabBoolean, DbabDateTime, DbabUuid, DbabJson
--- Schema:
---   DbabTable, DbabKey, DbabPK, DbabFK
--- Tab Bar:
---   DbabTabActive, DbabTabInactive, DbabTabActiveIndicator, DbabTabIconSaved, DbabTabIconUnsaved
--- Sidebar:
---   DbabSidebarIcon*, DbabSidebarText, DbabSidebarTextActive, DbabSidebarType
--- History:
---   DbabHistoryHeader, DbabHistoryTime, DbabHistoryVerb, DbabHistoryTarget, DbabHistoryDuration
