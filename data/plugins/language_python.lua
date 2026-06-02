-- mod-version:3
-- 2026-06-02 - Note for Amer
-- Simplified this Python highlighter to prioritize stable, conventional syntax
-- coloring over advanced signature and annotation parsing. Removed fragile
-- stateful rules that could leak docstring-like highlighting into later lines,
-- tightened quote handling around triple-quoted strings, and dropped unused
-- workaround/dead parsing code.
local syntax = require "core.syntax"

local function table_merge(a, b)
  local t = {}
  for _, v in ipairs(a) do table.insert(t, v) end
  for _, v in ipairs(b) do table.insert(t, v) end
  return t
end


local python_symbols = {
  ["class"]    = "keyword",
  ["finally"]  = "keyword",
  ["is"]       = "keyword",
  ["return"]   = "keyword",
  ["continue"] = "keyword",
  ["for"]      = "keyword",
  ["lambda"]   = "keyword",
  ["try"]      = "keyword",
  ["except"]   = "keyword",
  ["def"]      = "keyword",
  ["async"]    = "keyword",
  ["await"]    = "keyword",
  ["from"]     = "keyword",
  ["nonlocal"] = "keyword",
  ["while"]    = "keyword",
  ["and"]      = "keyword",
  ["global"]   = "keyword",
  ["not"]      = "keyword",
  ["with"]     = "keyword",
  ["as"]       = "keyword",
  ["elif"]     = "keyword",
  ["if"]       = "keyword",
  ["or"]       = "keyword",
  ["else"]     = "keyword",
  ["match"]    = "keyword",
  ["case"]     = "keyword",
  ["import"]   = "keyword",
  ["pass"]     = "keyword",
  ["break"]    = "keyword",
  ["in"]       = "keyword",
  ["del"]      = "keyword",
  ["raise"]    = "keyword",
  ["yield"]    = "keyword",
  ["assert"]   = "keyword",

  ["self"]     = "keyword2",

  ["None"]     = "literal",
  ["True"]     = "literal",
  ["False"]    = "literal",
}

local python_fexpr = {
  patterns = {
    { pattern = { '"', '"', '\\' }, type = "string" },
    { pattern = { "'", "'", '\\' }, type = "string" },
    { pattern = "%d+[%d%.eE_]*", type = "number" },
    { pattern = "0[xboXBO][%da-fA-F_]+", type = "number" },
    { pattern = "[%+%-=/%*%^%%<>!~|&:,%.%[%]()%?]", type = "operator" },
    { pattern = "[%a_][%w_]*%f[(]", type = "function" },
    { pattern = "[%a_][%w_]*", type = "symbol" },
  },
  symbols = python_symbols
}

local python_fstring = {
  patterns = {
    { pattern = "\\.", type = "string" },
    { pattern = "{{", type = "string" },
    { pattern = "}}", type = "string" },
    { pattern = { "{", "}" }, type = "normal", syntax = python_fexpr },
    { pattern = "[^\\{}\"']+", type = "string" },
  },
  symbols = {}
}


local python_patterns = {
  { pattern = "#.*", type = "comment" },

  { pattern = '[uUrR]%f["\']', type = "keyword" },

  { pattern = { '"""', '"""', '\\' }, type = "string" },
  { pattern = { "'''", "'''", '\\' }, type = "string" },
  { pattern = { '"', '"', '\\' }, type = "string" },
  { pattern = { "'", "'", '\\' }, type = "string" },

  { pattern = { 'f"', '"', "\\" }, type = "string", syntax = python_fstring },
  { pattern = { "f'", "'", "\\" }, type = "string", syntax = python_fstring },

  { pattern = "%d+[%d%.eE_]*", type = "number" },
  { pattern = "0[xboXBO][%da-fA-F_]+", type = "number" },
  { pattern = "%.?%d+", type = "number" },
  { pattern = "%f[-%w_]-%f[%d%.]", type = "number" },

  { pattern = "[%+%-=/%*%^%%<>!~|&:]", type = "operator" },
  { pattern = "[%a_][%w_]*%f[(]", type = "function" },

  { pattern = "[%a_][%w_]+", type = "symbol" },
}


syntax.add {
  name = "Python",
  files = { "%.py$", "%.pyw$", "%.rpy$", "%.pyi$" },
  headers = "^#!.*[ /]python",
  comment = "#",

  patterns = table_merge({
    { pattern = "def%s+()[%a_][%w_]*", type = { "keyword", "function" } },
    { pattern = "class%s+()[%a_][%w_]+().*:",
      type = { "keyword", "keyword2", "normal" }
    },

  }, python_patterns),

  symbols = python_symbols
}
