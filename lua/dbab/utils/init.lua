local M = {}

M.parser = require "dbab.utils.parser"

local layout = {
  { "sidebar", "editor" },
  { "hisotry", "grid" },
}

local layout = {
  { "sidebar", "hisotry", "editor" },
  { "grid" },
}

return M
