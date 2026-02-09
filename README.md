# dbab.nvim

A lightweight database client for Neovim. Query databases directly from your editor.

![dbab.nvim](./screenshots/main.png)

## Features

- **Multi-database support**: PostgreSQL, MySQL, MariaDB, SQLite
- **Flexible layout**: Choose from presets or define your own pane arrangement
- **Schema browser**: Navigate schemas, tables, and columns in sidebar
- **Query editor**: Write and execute SQL with syntax highlighting
- **Query history**: Track executed queries with timing, re-execute or load to editor
- **Multiple query tabs**: Work with multiple queries simultaneously
- **Save queries**: Store frequently used queries per connection
- **Result viewer**: Multiple display styles (table, json, vertical, markdown, raw) with type-aware highlighting

## Layout

### Classic (default)

![Classic Layout](./screenshots/layout-classic.png)

```
┌─────────────────────┬─────────────────────────────────────┐
│ Sidebar (20%)       │ Query Editor (80%)                  │
├─────────────────────┼─────────────────────────────────────┤
│ History (20%)       │ Result Viewer (80%)                 │
└─────────────────────┴─────────────────────────────────────┘
```

### Wide

![Wide Layout](./screenshots/layout-wide.png)

```
┌─────────────────────┬─────────────────────┬───────────────┐
│ Sidebar (33%)       │ Query Editor (34%)  │ History (33%) │
├───────────────────────────────────────────────────────────┤
│                    Result Viewer (100%)                   │
└───────────────────────────────────────────────────────────┘
```

## Requirements

- Neovim >= 0.9.0
- Database CLI tools:
  - `psql` for PostgreSQL
  - `mysql` for MySQL
  - `sqlite3` for SQLite
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)

## Installation

### lazy.nvim

```lua
{
  "zerochae/dbab.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "hrsh7th/nvim-cmp", -- Optional: for autocompletion
  },
  config = function()
    require("dbab").setup({
      connections = {
        { name = "local", url = "postgres://user:pass@localhost:5432/mydb" },
        { name = "prod", url = "$DATABASE_URL" }, -- supports env vars
      },
    })
  end,
}
```

## Autocompletion (Optional)

If you use `nvim-cmp`, add `dbab` to your sources to enable SQL autocompletion (tables, columns, keywords):

```lua
require("cmp").setup({
  sources = {
    { name = "dbab" },
    -- other sources...
  },
})
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:Dbab` | Open dbab sidebar |
| `:DbabClose` | Close dbab |

### Sidebar Keymaps

| Key | Action |
|-----|--------|
| `<CR>` / `o` | Toggle node / Open query |
| `<Tab>` | Move to editor |
| `S` | Select table (SELECT *) |
| `i` | Insert table (INSERT template) |
| `d` | Delete saved query |
| `q` | Close |

### Editor Keymaps

| Key | Action |
|-----|--------|
| `<CR>` | Execute query |
| `<C-s>` | Save query |
| `gt` / `gT` | Next / Previous tab |
| `<Leader>w` | Close tab |
| `<Tab>` | Move to result |
| `q` | Close |

### History Keymaps

| Key | Action |
|-----|--------|
| `<CR>` | Load or execute query (based on config) |
| `R` | Re-execute query immediately |
| `y` | Copy query to clipboard |
| `d` | Delete entry |
| `C` | Clear all history |
| `<Tab>` | Move to sidebar |
| `<S-Tab>` | Move to result |
| `q` | Close |

### Result Keymaps

| Key | Action |
|-----|--------|
| `y` | Yank current row as JSON |
| `Y` | Yank all rows as JSON |
| `<Tab>` | Move to sidebar |
| `<S-Tab>` | Move to editor |
| `q` | Close |

## Screenshots

### Schema Browser
![Schema Browser](./screenshots/sidebar.png)

### Query Result with Type Highlighting
![Result Viewer](./screenshots/result.png)

### Query History
![Query History](./screenshots/history.png)

## Configuration

```lua
require("dbab").setup({
  connections = {
    { name = "local", url = "postgres://localhost/mydb" },
  },
  layout = "classic",  -- "classic" | "wide" | custom layout table
  sidebar = {
    width = 0.2,
    use_brand_icon = false,   -- true: per-DB icons, false: generic db icon
    use_brand_color = false,  -- true: per-DB brand colors, false: single color (Number)
    show_brand_name = false,  -- true: show [postgres] label, false: icon + name only
  },
  editor = {
    show_tabbar = true,       -- show tab bar above editor
  },
  grid = {
    max_width = 120,
    max_height = 20,
    show_line_number = true,
    header_align = "fit",     -- "fit" or "full"
    style = "table",          -- "table", "json", "raw", "vertical", "markdown"
  },
  history = {
    width = 0.2,
    style = "compact",        -- "compact" or "detailed"
    max_entries = 100,
    on_select = "execute",    -- "execute" or "load"
    persist = true,
    filter_by_connection = true,
    query_display = "auto",   -- "short", "full", or "auto"
    short_hints = { "where", "join", "order", "group", "limit" },
  },
  schema = {
    show_system_schemas = true,
  },
  keymaps = {
    open = "<Leader>db",
    execute = "<CR>",
    close = "q",
    sidebar = {
      toggle_expand = { "<CR>", "o" },
      refresh = "R",
      rename = "r",
      new_query = "n",
      copy_name = "y",
      insert_template = "i",
      delete = "d",
      copy_query = "c",
      paste_query = "p",
      to_editor = "<Tab>",
      to_history = "<S-Tab>",
    },
    history = {
      select = "<CR>",
      execute = "R",
      copy = "y",
      delete = "d",
      clear = "C",
      to_sidebar = "<Tab>",
      to_result = "<S-Tab>",
    },
    editor = {
      execute_insert = "<C-CR>",
      execute_leader = "<Leader>r",
      save = "<C-s>",
      next_tab = "gt",
      prev_tab = "gT",
      close_tab = "<Leader>w",
      to_result = "<Tab>",
      to_sidebar = "<S-Tab>",
    },
    result = {
      yank_row = "y",
      yank_all = "Y",
      to_sidebar = "<Tab>",
      to_editor = "<S-Tab>",
    },
  },
  highlights = {
    -- Override any Dbab highlight group
    -- DbabHeader = { bg = "#ff6600", fg = "#000000" },
  },
})
```

### Layout Presets

| Preset | Description |
|--------|-------------|
| `"classic"` | 4-pane layout (sidebar 20%, history 20%) |
| `"wide"` | 3-column top + full-width bottom (sidebar 33%, history 33%) |

### Custom Layout

Define your own pane arrangement:

```lua
-- No history panel
layout = {
  { "sidebar", "editor" },
  { "grid" },
}

-- Editor on the left
layout = {
  { "editor", "sidebar" },
  { "grid", "history" },
}
```

Components: `"sidebar"`, `"editor"`, `"history"`, `"grid"` (editor and grid are required)

### Result Styles

Configure with `grid.style`:

| Style | Description |
|-------|-------------|
| `"table"` | Table grid with zebra striping and type-aware highlighting (default) |
| `"json"` | JSON format with Treesitter syntax highlighting |
| `"vertical"` | One record per block, column names on the left (like `psql \x`) |
| `"markdown"` | Markdown table with Treesitter syntax highlighting |
| `"raw"` | Unprocessed CLI output |

```lua
grid = {
  style = "vertical",
},
```

#### table

![style-table](./screenshots/result.png)


#### raw

![style-raw](./screenshots/style-raw.png)

#### json

![style-json](./screenshots/style-json.png)

#### vertical

![style-vertical](./screenshots/style-vertical.png)

#### markdown

![style-markdown](./screenshots/style-markdown.png)

### History Styles

Configure with `history.style`:

| Style | Description |
|-------|-------------|
| `"compact"` | One line per entry with verb, target, hints (default) |
| `"detailed"` | Multi-line: full query with syntax highlighting + metadata below |

```lua
history = {
  style = "detailed",
},
```

### Sidebar Display Options

Control how database connections appear in the sidebar:

```lua
sidebar = {
  use_brand_icon = false,   -- default
  use_brand_color = false,  -- default
  show_brand_name = false,  -- default
},
```

| Option | `false` (default) | `true` |
|--------|-------------------|--------|
| `use_brand_icon` | Generic DB icon for all connections | Per-DB brand icons (PostgreSQL, MySQL, etc.) |
| `use_brand_color` | Single color (`Number` highlight) | Per-DB brand colors (blue, red, green, etc.) |
| `show_brand_name` | `icon my_db` | `icon [postgres] my_db` |

## Highlight Groups

All highlight groups can be overridden by defining them before `setup()`.
Groups marked with **(computed)** are always recalculated based on your colorscheme.

### Grid

| Group | Default | Description |
|-------|---------|-------------|
| `DbabRowOdd` | **(computed)** | Odd row background |
| `DbabRowEven` | **(computed)** | Even row background |
| `DbabHeader` | **(computed)** | Grid header (from `Function` fg) |
| `DbabSeparator` | `Comment` | Grid separator lines |
| `DbabCellActive` | `CursorLine` | Active cell |

### Window

| Group | Default | Description |
|-------|---------|-------------|
| `DbabFloat` | `NormalFloat` | Float window background |
| `DbabBorder` | `WinSeparator` | Window border |
| `DbabTitle` | `Title` | Window title |

### Data Types

| Group | Default | Description |
|-------|---------|-------------|
| `DbabNull` | `Comment` | NULL values |
| `DbabNumber` | `Number` | Numeric values |
| `DbabString` | `Normal` | String values |
| `DbabBoolean` | `Boolean` | Boolean values |
| `DbabDateTime` | `Special` | Date/time values |
| `DbabUuid` | `Constant` | UUID values |
| `DbabJson` | `Function` | JSON values |

### Schema

| Group | Default | Description |
|-------|---------|-------------|
| `DbabTable` | `Type` | Table names |
| `DbabKey` | `Keyword` | Key names |
| `DbabPK` | `DiagnosticError` | Primary key (bold) |
| `DbabFK` | `Function` | Foreign key (bold) |

### Sidebar

| Group | Default | Description |
|-------|---------|-------------|
| `DbabIconDb` | `Number` | Default DB icon color (`use_brand_color = false`) |
| `DbabIconPostgres` | `fg=#4169E1` | PostgreSQL brand color (bold) |
| `DbabIconMysql` | `fg=#4479A1` | MySQL brand color (bold) |
| `DbabIconMariadb` | `fg=#003545` | MariaDB brand color (bold) |
| `DbabIconSqlite` | `fg=#003B57` | SQLite brand color (bold) |
| `DbabIconRedis` | `fg=#FF4438` | Redis brand color (bold) |
| `DbabIconMongodb` | `fg=#47A248` | MongoDB brand color (bold) |
| `DbabSidebarIconConnection` | `Number` | Connection icon |
| `DbabSidebarIconActive` | `String` | Active connection icon |
| `DbabSidebarIconNewQuery` | `Function` | New query icon |
| `DbabSidebarIconBuffers` | `Function` | Buffers icon |
| `DbabSidebarIconSaved` | `Keyword` | Saved queries icon |
| `DbabSidebarIconSchemas` | `Special` | Schemas icon |
| `DbabSidebarIconSchema` | `Type` | Schema icon |
| `DbabSidebarIconTable` | `Type` | Table icon |
| `DbabSidebarIconColumn` | `Function` | Column icon |
| `DbabSidebarIconPK` | `DiagnosticError` | Primary key icon |
| `DbabSidebarText` | `Normal` | Default text |
| `DbabSidebarTextActive` | `String` | Active item text (bold) |
| `DbabSidebarType` | `Comment` | Type annotation |

### History

| Group | Default | Description |
|-------|---------|-------------|
| `DbabHistoryHeader` | `Title` | Section header (bold) |
| `DbabHistoryRowOdd` | **(computed)** | Odd row background |
| `DbabHistoryRowEven` | **(computed)** | Even row background |
| `DbabHistoryTime` | `Comment` | Timestamp |
| `DbabHistoryVerb` | `Keyword` | SQL verb |
| `DbabHistoryTarget` | `Type` | Target table name |
| `DbabHistoryDuration` | `Number` | Execution duration |
| `DbabHistoryConnName` | `Normal` | Connection name |
| `DbabHistorySelect` | `Function` | SELECT queries |
| `DbabHistoryInsert` | `String` | INSERT queries |
| `DbabHistoryUpdate` | `Type` | UPDATE queries |
| `DbabHistoryDelete` | `DiagnosticError` | DELETE queries |
| `DbabHistoryCreate` | `String` | CREATE statements |
| `DbabHistoryDrop` | `DiagnosticError` | DROP statements |
| `DbabHistoryAlter` | `Special` | ALTER statements |
| `DbabHistoryTruncate` | `DiagnosticWarn` | TRUNCATE statements |

Hint badges (compact mode):

| Group | Default | Description |
|-------|---------|-------------|
| `DbabHistoryHintWhere` | `DiagnosticWarn` | WHERE clause |
| `DbabHistoryHintJoin` | `Special` | JOIN clause |
| `DbabHistoryHintOrder` | `Keyword` | ORDER BY |
| `DbabHistoryHintGroup` | `Type` | GROUP BY |
| `DbabHistoryHintLimit` | `Number` | LIMIT |

### Tab Bar

| Group | Default | Description |
|-------|---------|-------------|
| `DbabTabActive` | `bg=#3a3a4a` | Active tab (bold) |
| `DbabTabActiveIcon` | `bg=#3a3a4a fg=#a6e3a1` | Active tab icon |
| `DbabTabInactive` | `Comment` | Inactive tab |
| `DbabTabInactiveIcon` | `Comment` | Inactive tab icon |
| `DbabTabModified` | `DiagnosticWarn` | Modified indicator |
| `DbabTabIconSaved` | `String` | Saved query icon |
| `DbabTabIconUnsaved` | `Function` | Unsaved query icon |
| `DbabTabbarBg` | `Normal` | Tab bar background |

### Customization

Override highlights via `setup()`:

```lua
require("dbab").setup({
  highlights = {
    DbabHeader = { bg = "#ff6600", fg = "#000000" },
    DbabNull = { fg = "#555555", italic = true },
  },
})
```

## Connection URL Format

```
postgres://user:password@host:port/database
mysql://user:password@host:port/database
mariadb://user:password@host:port/database
sqlite:///path/to/database.db
```

Environment variables are supported: `$DATABASE_URL` or `${DATABASE_URL}`

## Acknowledgements

This project was inspired by excellent existing plugins:

- [vim-dadbod-ui](https://github.com/kristijanhusak/vim-dadbod-ui): The classic DB UI for Vim/Neovim.
- [nvim-dbee](https://github.com/kndndrj/nvim-dbee): A modern approach to DB client in Neovim.

`dbab.nvim` aims to provide a lightweight alternative with a modern Lua-based UI while leveraging the robust backend of [vim-dadbod](https://github.com/tpope/vim-dadbod).

## License

MIT
