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

---@class Dbab.UIConfig
---@field grid Dbab.GridConfig
---@field sidebar Dbab.SidebarUIConfig
---@field history Dbab.HistoryUIConfig

---@class Dbab.SidebarUIConfig
---@field position "left"|"right" Sidebar position
---@field width number Width as percentage (0.1~1.0)
---@field show_history boolean Show history panel in sidebar bottom
---@field history_ratio number Ratio of sidebar height for history (0.1~0.9)

---@class Dbab.HistoryUIConfig
---@field position "left"|"right" History panel position
---@field width number Width as percentage (0.1~1.0)

---@class Dbab.GridConfig
---@field max_width number Maximum grid width
---@field max_height number Maximum grid height
---@field show_line_number boolean Show line numbers in result grid

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
---@field execute string Keymap to execute query

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
