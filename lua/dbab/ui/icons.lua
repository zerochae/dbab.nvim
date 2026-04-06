-- stylua: ignore start
local M = {
  -- DB types
  postgres       = "",
  mysql          = "",
  mariadb        = "",
  sqlite         = "",
  redis          = "",
  mongodb        = "",
  db_default     = "󰆼",

  -- sidebar tree
  explorer       = "󰙅",
  query_file     = "󰈙",
  query_modified = "󰏪",
  open_buffer    = "󰓰",
  saved_queries  = "󱔗",
  new_action     = "󱪝",
  schemas        = "󰒋",
  schema_node    = "󰙅",
  tables         = "󰓱",
  tbl            = "󰓫",
  view           = "󰈈",
  column         = "󰠵",
  column_pk      = "󰌋",

  -- status
  connected      = "✓",
  loading        = "◐",
  idle           = "○",

  -- result winbar
  time           = "󰅐",
  rows           = "󰓫",
  duration       = "󱎫",
  result         = "󰓫",

  -- tab bar
  separator      = " ",

  -- history
  history        = "󰋚",
  header         = "󰙅",

  -- SQL verb icons
  verb_select    = "󰁕",
  verb_insert    = "󰁔",
  verb_update    = "󰁓",
  verb_delete    = "󰁒",
  verb_create    = "󰙴",
  verb_drop      = "󰆴",
  verb_alter     = "󰏫",
  verb_truncate  = "󰆴",
  verb_default   = "󰘥",

  -- mutation result icons (workbench)
  mut_update     = "󰏫",
  mut_delete     = "󰆴",
  mut_insert     = "󰐕",
  mut_create     = "󰙴",
}
-- stylua: ignore end

M.db_map = {
	postgres = M.postgres,
	mysql = M.mysql,
	mariadb = M.mariadb,
	sqlite = M.sqlite,
	redis = M.redis,
	mongodb = M.mongodb,
	unknown = M.db_default,
}

M.verb_map = {
	SEL = M.verb_select,
	INS = M.verb_insert,
	UPD = M.verb_update,
	DEL = M.verb_delete,
	CRT = M.verb_create,
	DRP = M.verb_drop,
	ALT = M.verb_alter,
	TRC = M.verb_truncate,
}

---@param db_type string
---@return string
function M.db(db_type)
	return M.db_map[db_type] or M.db_default
end

---@param verb string
---@return string
function M.verb(verb)
	return (M.verb_map[verb] or M.verb_default) .. " "
end

return M
