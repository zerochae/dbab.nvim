# dbab.nvim

A lightweight database client for Neovim. Query databases directly from your editor.

## Features

- **Multi-database support**: PostgreSQL, MySQL, SQLite
- **Flexible layout**: Choose from presets or define your own pane arrangement
- **Schema browser**: Navigate schemas, tables, and columns in sidebar
- **Query editor**: Write and execute SQL with syntax highlighting
- **Query history**: Track executed queries with timing, re-execute or load to editor
- **Multiple query tabs**: Work with multiple queries simultaneously
- **Save queries**: Store frequently used queries per connection
- **Result viewer**: View results with zebra striping and type-aware highlighting

## Layout

### Classic (default)
```
┌─────────────────────┬─────────────────────────────────────┐
│ Sidebar (20%)       │ Query Editor (80%)                  │
├─────────────────────┼─────────────────────────────────────┤
│ History (20%)       │ Result Viewer (80%)                 │
└─────────────────────┴─────────────────────────────────────┘
```

### Wide
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
  dependencies = { "MunifTanjim/nui.nvim" },
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
    },
  },
  keymaps = {
    open = "<Leader>db",
    execute = "<CR>",
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

## Connection URL Format

```
postgres://user:password@host:port/database
mysql://user:password@host:port/database
sqlite:///path/to/database.db
```

Environment variables are supported: `$DATABASE_URL` or `${DATABASE_URL}`

## License

MIT
