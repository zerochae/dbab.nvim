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
  ui = {
    -- Layout preset: "classic" or "wide"
    layout = "classic",
    -- Or define custom layout:
    -- layout = {
    --   { "sidebar", "editor" },
    --   { "history", "grid" },
    -- },
    sidebar = { width = 0.2 },
    history = { width = 0.2 },
    grid = {
      max_width = 120,
      max_height = 20,
      show_line_number = true,
      header_align = "fit",  -- "fit" or "full"
      style = "table", -- "table" (default), "json", "raw", "vertical", "markdown"
    },
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
  schema = {
    show_system_schemas = true,
  },
  history = {
    max_entries = 100,
    on_select = "execute",          -- "execute" or "load"
    persist = true,
    filter_by_connection = true,
    query_display = "auto",         -- "short", "full", or "auto"
    short_hints = { "where", "join", "order", "group", "limit" },
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

Configure with `ui.grid.style`:

| Style | Description |
|-------|-------------|
| `"table"` | Table grid with zebra striping and type-aware highlighting (default) |
| `"json"` | JSON format with Treesitter syntax highlighting |
| `"vertical"` | One record per block, column names on the left (like `psql \x`) |
| `"markdown"` | Markdown table with Treesitter syntax highlighting |
| `"raw"` | Unprocessed CLI output |

```lua
ui = {
  grid = {
    style = "vertical",
  },
}
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
