local test = require "core.test"
local config = require "core.config"
local tokenizer = require "core.tokenizer"

local function collect_each_token(tokens, scol)
  local items = {}
  for _, type, text in tokenizer.each_token(tokens, scol) do
    table.insert(items, { type, text })
  end
  return items
end

test.describe("tokenizer", function()
  test.test("toggles the native module while keeping each_token", function()
    local original = config.native_tokenizer
    local syntax = {
      patterns = {
        { pattern = "%d+", type = "number" }
      },
      symbols = {}
    }
    config.native_tokenizer = true
    test.ok(tokenizer.set_use_native(true))
    test.equal(tokenizer.is_using_native(), true)
    tokenizer.tokenize(syntax, "123", string.char(0))
    test.type(tokenizer._tokenizer_native_text_arena, "userdata")
    test.type(tokenizer._tokenizer_native_token_arena, "userdata")
    tokenizer.set_use_native(false)
    test.equal(tokenizer.is_using_native(), false)
    test.equal(tokenizer._tokenizer_native_text_arena, nil)
    test.equal(tokenizer._tokenizer_native_token_arena, nil)
    tokenizer.set_use_native(true)
    test.equal(tokenizer.is_using_native(), true)
    config.native_tokenizer = original
    tokenizer.set_use_native(original ~= false)
    test.type(tokenizer.each_token, "function")
  end)

  test.test("clears cached native syntax userdata", function()
    local nested = {
      patterns = {
        { pattern = "%d+", type = "number" }
      },
      symbols = {}
    }
    local syntax = {
      patterns = {
        { pattern = { '"', '"' }, type = "string", syntax = nested },
        { pattern = "[%a_]+", type = "symbol" }
      },
      symbols = {}
    }

    tokenizer.set_use_native(true)
    tokenizer.tokenize(syntax, [["123"]], string.char(0))
    test.type(tokenizer._tokenizer_native_text_arena, "userdata")
    test.type(tokenizer._tokenizer_native_token_arena, "userdata")
    test.type(syntax._tokenizer_native_cache, "userdata")
    test.type(nested._tokenizer_native_cache, "userdata")

    tokenizer.clear_native_cache(syntax)
    test.equal(syntax._tokenizer_native_cache, nil)
    test.equal(nested._tokenizer_native_cache, nil)
  end)

  test.test("tokenizes regex captures and preserves token merging", function()
    local syntax = {
      patterns = {
        { regex = "0()[0-7]+", type = { "keyword", "number" } },
        { pattern = "%s+", type = "normal" },
        { pattern = "[%a_]+", type = "keyword" }
      },
      symbols = {}
    }

    local tokens, state = tokenizer.tokenize(syntax, "077 foo", string.char(0))
    test.equal(state, string.char(0))
    test.same(tokens, {
      "keyword", "0",
      "number", "77",
      "keyword", " foo"
    })
  end)

  test.test("keeps regex matches after normal text", function()
    local syntax = {
      patterns = {
        { regex = [[-?\d+]], type = "number" },
        { pattern = "[=]", type = "operator" },
        { pattern = "[%a_][%w_]*", type = "symbol" }
      },
      symbols = {}
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    local tokens, state = tokenizer.tokenize(syntax, "(3==value", string.char(0))
    tokenizer.set_use_native(using_native)

    test.equal(state, string.char(0))
    test.same(tokens, {
      "normal", "(",
      "number", "3",
      "operator", "==",
      "symbol", "value"
    })
  end)

  test.test("tokenizes lua patterns with multiple position captures", function()
    local syntax = {
      patterns = {
        {
          pattern = "static()%s+()const",
          type = { "keyword", "normal", "keyword" }
        }
      },
      symbols = {}
    }

    local tokens, state = tokenizer.tokenize(syntax, "static const", string.char(0))
    test.equal(state, string.char(0))
    test.same(tokens, {
      "keyword", "static",
      "keyword", " const"
    })
  end)

  test.test("tokenizes common language pattern shapes with native fast paths", function()
    local syntax = {
      patterns = {
        { pattern = "//.*", type = "comment" },
        { pattern = { "/%*", "%*/" }, type = "comment" },
        { pattern = { '"', '"', '\\' }, type = "string" },
        { pattern = "[%+%-=/%*]", type = "operator" },
        { pattern = "[%a_][%w_]*", type = "symbol" },
      },
      symbols = {
        ["let"] = "keyword"
      }
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    local tokens, state = tokenizer.tokenize(
      syntax,
      [[let value = "text" // trailing]],
      string.char(0)
    )
    tokenizer.set_use_native(using_native)

    test.equal(state, string.char(0))
    test.same(tokens, {
      "keyword", "let",
      "symbol", " value",
      "operator", " =",
      "string", ' "text"',
      "comment", " // trailing"
    })
  end)

  test.test("reports native syntax compilation stats", function()
    local syntax = {
      patterns = {
        { pattern = "[%a_][%w_]*", type = "symbol" },
        { regex = [[\d+]], type = "number" },
        { pattern = "%s+", type = "normal" },
      },
      symbols = {}
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    tokenizer.tokenize(syntax, "name 123", string.char(0))
    local stats = tokenizer.get_syntax_stats(syntax)
    tokenizer.set_use_native(using_native)

    test.type(stats, "table")
    test.equal(stats.patterns, 3)
    test.type(stats.compiled_patterns, "number")
    test.type(stats.fallback_patterns, "number")
    test.type(stats.skipped_by_starter, "number")
    test.type(stats.pattern_stats, "table")
    test.equal(#stats.pattern_stats, 3)
  end)

  test.test("keeps non-ascii identifiers on the utf8 pattern fallback", function()
    local syntax = {
      patterns = {
        { pattern = "[%a_][%w_]*", type = "symbol" },
        { pattern = "[%+%-=]", type = "operator" }
      },
      symbols = {}
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    local tokens, state = tokenizer.tokenize(syntax, "café = año", string.char(0))
    tokenizer.set_use_native(using_native)

    test.equal(state, string.char(0))
    test.same(tokens, {
      "symbol", "café",
      "operator", " =",
      "symbol", " año"
    })
  end)

  test.test("keeps optional leading lua pattern atoms searchable", function()
    local syntax = {
      patterns = {
        { pattern = "%.?%d+", type = "number" },
        { pattern = "[%a_][%w_]*", type = "symbol" },
        { pattern = "%s+", type = "normal" },
      },
      symbols = {}
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    local tokens, state = tokenizer.tokenize(syntax, "value 1 .2", string.char(0))
    tokenizer.set_use_native(using_native)

    test.equal(state, string.char(0))
    test.same(tokens, {
      "symbol", "value",
      "number", " 1",
      "number", " .2"
    })
  end)

  test.test("tokenizes balanced quoted strings with matching delimiters", function()
    local syntax = {
      patterns = {
        {
          pattern = "@type%s+()%b\"\"",
          type = { "annotation", "annotation.string" }
        },
        {
          pattern = "|%s*()%b\"\"",
          type = { "annotation.operator", "annotation.string" }
        },
        { pattern = "[%w%p]+", type = "comment" }
      },
      symbols = {}
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    local tokens, state = tokenizer.tokenize(syntax, '@type "all" | "background"', string.char(0))
    tokenizer.set_use_native(using_native)

    test.equal(state, string.char(0))
    test.same(tokens, {
      "annotation", "@type ",
      "annotation.string", '"all"',
      "annotation.operator", " | ",
      "annotation.string", '"background"'
    })
  end)

  test.test("tokenizes balanced parentheses in Lua patterns", function()
    local syntax = {
      patterns = {
        { pattern = "fun%s*%b()", type = "annotation.type" },
        { pattern = "[%w%p]+", type = "comment" }
      },
      symbols = {}
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    local tokens, state = tokenizer.tokenize(
      syntax,
      'fun(status: "accept"|"cancel", result: string[]|string|nil)',
      string.char(0)
    )
    tokenizer.set_use_native(using_native)

    test.equal(state, string.char(0))
    test.same(tokens, {
      "annotation.type", 'fun(status: "accept"|"cancel", result: string[]|string|nil)'
    })
  end)

  test.test("does not restart regex matching after a subsyntax ends the line", function()
    local original = tokenizer.is_using_native()
    for _, native in ipairs { false, true } do
      for _, text in ipairs { "<name>", "<\195\169>" } do
        local syn = {
          patterns = {
            {
              regex = { "<", ">" }, type = "string",
              syntax = {
                patterns = { { pattern = "[^>]+", type = "string" } },
                symbols = {},
              },
            },
          },
          symbols = {},
        }
        tokenizer.set_use_native(native)
        if not native then
          debug.sethook(function() error("tokenizer did not finish the line") end, "", 100000)
        end
        local ok, tokens, state = pcall(tokenizer.tokenize, syn, text, string.char(0))
        debug.sethook()
        tokenizer.set_use_native(original)
        test.ok(ok, tostring(tokens))
        test.same(tokens, { "string", text })
        test.equal(state, string.char(0))
      end
    end
  end)

  test.test("does not close subsyntax on escaped delimiters", function()
    local string_syntax = {
      patterns = {
        { pattern = "%$[%a_][%w_]*", type = "keyword2" },
        { pattern = "[^\"]", type = "string" },
        { pattern = "%p", type = "string" }
      },
      symbols = {}
    }
    local syntax = {
      patterns = {
        { pattern = { '"', '"', '\\' }, type = "string", syntax = string_syntax }
      },
      symbols = {}
    }

    local tokens, state = tokenizer.tokenize(syntax, [["$name=\"$value\" "]], string.char(0))
    test.equal(state, string.char(0))
    test.same(tokens, {
      "string", '"',
      "keyword2", "$name",
      "string", '=\\"',
      "keyword2", "$value",
      "string", '\\" "'
    })
  end)

  test.test("handles zero-width regex subsyntax openers at line start", function()
    local signature_syntax = {
      patterns = {
        { pattern = "[%a_][%w_]*", type = "symbol" }
      },
      symbols = {
        ["function"] = "keyword"
      }
    }
    local syntax = {
      patterns = {
        {
          regex = { [[(?=function\s+[a-z_][a-z0-9_]*\s*\()]], [[\)]] },
          type = "normal",
          syntax = signature_syntax
        },
        { pattern = "[%a_][%w_]*", type = "normal" }
      },
      symbols = {}
    }

    local tokens, state = tokenizer.tokenize(syntax, "function demo(", string.char(0))
    test.equal(state, string.char(1))
    test.same(tokens, {
      "keyword", "function",
      "symbol", " demo",
      "normal", "("
    })
  end)

  test.test("closes zero-width regex subsyntax on the same line", function()
    local signature_syntax = {
      patterns = {
        { pattern = "[%a_][%w_]*", type = "symbol" }
      },
      symbols = {
        ["function"] = "keyword"
      }
    }
    local syntax = {
      patterns = {
        {
          regex = {
            [[(?=function\s+[a-zA-Z_][a-zA-Z0-9_\.:]*\s*\()]],
            [[\)]]
          },
          type = "normal",
          syntax = signature_syntax
        },
        { pattern = "[%a_][%w_]*", type = "normal" }
      },
      symbols = {}
    }
    local using_native = tokenizer.is_using_native()

    tokenizer.set_use_native(true)
    local tokens, state = tokenizer.tokenize(
      syntax,
      "function Highlighter:reset()\n",
      string.char(0)
    )
    tokenizer.set_use_native(using_native)

    test.equal(state, string.char(0))
    test.same(tokens, {
      "keyword", "function",
      "symbol", " Highlighter",
      "normal", ":",
      "symbol", "reset",
      "normal", "()\n"
    })
  end)

  test.test("tracks subsyntax state and extracts subsyntaxes", function()
    local inner = {
      name = "inner",
      patterns = {
        { pattern = { '"', '"', '\\' }, type = "string" }
      },
      symbols = {}
    }
    local syntax = {
      name = "outer",
      patterns = {
        { pattern = { "%[", "%]" }, type = "operator", syntax = inner }
      },
      symbols = {}
    }

    local open_tokens, open_state = tokenizer.tokenize(syntax, "[", string.char(0))
    test.same(open_tokens, { "operator", "[" })
    test.equal(open_state, string.char(1))

    local syntaxes = tokenizer.extract_subsyntaxes(syntax, open_state)
    test.equal(#syntaxes, 1)
    test.equal(syntaxes[1], inner)

    local close_tokens, close_state = tokenizer.tokenize(syntax, "]", open_state)
    test.same(close_tokens, { "operator", "]" })
    test.equal(close_state, string.char(0))
  end)

  test.test("supports resuming from incomplete tokenization", function()
    local syntax = {
      patterns = { { pattern = "%a+", type = "keyword" } },
      symbols = {}
    }
    local original_get_time = system.get_time
    local original_co_max_time = core.co_max_time
    local tick = 0

    system.get_time = function()
      tick = tick + 1
      return tick
    end
    core.co_max_time = 0.0001

    local text = string.rep("a", 256)
    local partial_tokens, partial_state, resume = tokenizer.tokenize(syntax, text, string.char(0))

    system.get_time = original_get_time
    core.co_max_time = original_co_max_time

    test.equal(partial_state, string.char(0))
    test.type(resume, "table")
    test.equal(partial_tokens[#partial_tokens - 1], "incomplete")

    local final_tokens, final_state = tokenizer.tokenize(syntax, text, partial_state, resume)
    test.same(final_tokens, { "keyword", text })
    test.equal(final_state, string.char(0))
  end)

  test.test("iterates token slices with each_token", function()
    local items = collect_each_token({ "keyword", "abc", "normal", " def" }, 3)
    test.same(items, {
      { "keyword", "c" },
      { "normal", " def" }
    })

    items = collect_each_token({ "keyword", "abc", "normal", " def" }, 4)
    test.same(items, {
      { "normal", " def" }
    })

    items = collect_each_token({ "keyword", "abc", "normal", " def" }, 6)
    test.same(items, {
      { "normal", "ef" }
    })

    items = collect_each_token({ "keyword", "abc", "normal", " def" }, 8)
    test.same(items, {})
  end)
end)

test.describe("regex starter fallback", function()
  test.before_each(function(context)
    context.native = tokenizer.is_using_native()
  end)

  test.after_each(function(context)
    tokenizer.set_use_native(context.native)
  end)

  test.test("Janet decimal expressions agree across backends", function()
    local expressions = {
      [[[-+]?(?:\d[\d_]*\.?[\d_]*|\.[\d_]+)(?:[eE&][-+]?\d+)?(?![\w.&])]],
      [[(?:[-+]?)(?:\d[\d_]*\.?[\d_]*|\.[\d_]+)(?:[eE&][-+]?\d+)?(?![\w.&])]],
    }
    for _, native in ipairs { false, true } do
      tokenizer.set_use_native(native)
      for _, expression in ipairs(expressions) do
        -- Also exercise per-pattern filtering when another rule can start here.
        for _, fallback in ipairs { false, true } do
          local syn = { patterns = {
            { regex = expression, type = "number" },
          }, symbols = {} }
          if fallback then
            table.insert(syn.patterns, { pattern = "[%w_.&]+", type = "normal" })
          end
          for _, text in ipairs {
            "123", "1_000", "123.45", ".45", "-123", "+.45",
            "123e10", "1.5e-3", ".5e3", "123&10", "1.e5",
          } do
            local tokens, state = tokenizer.tokenize(syn, text)
            test.same(tokens, { "number", text })
            test.equal(state, string.char(0))
            test.same(tokenizer.tokenize(syn, "(" .. text .. ")"),
              { "normal", "(", "number", text, "normal", ")" })
          end
          for _, text in ipairs { "123abc", "123.foo", "123&" } do
            test.same(tokenizer.tokenize(syn, text), { "normal", text })
          end
          if native then
            local stats = tokenizer.get_syntax_stats(syn)
            test.equal(stats.pattern_stats[1].unknown_starter, true)
            test.equal(stats.has_unknown_starters, true)
          end
        end
      end
    end
  end)

  test.test("optional prefixes cannot restrict unknown following atoms", function()
    for _, native in ipairs { false, true } do
      tokenizer.set_use_native(native)
      for _, prefix in ipairs { "[-+]?", "[-+]*", "[-+]{0,1}" } do
        for _, tail in ipairs { [[(?:\d+)]], [[.\d+]], "[^x]+" } do
          local syn = { patterns = {
            { regex = prefix .. tail, type = "number" },
          }, symbols = {} }
          for _, text in ipairs { "123", "-123" } do
            test.same(tokenizer.tokenize(syn, text), { "number", text })
          end
          if native then
            test.equal(tokenizer.get_syntax_stats(syn).pattern_stats[1].unknown_starter, true)
          end
        end
      end
    end
  end)

  test.test("supported optional prefixes retain starter filtering", function()
    tokenizer.set_use_native(true)
    local syn = { patterns = {
      { regex = [[[-+]?\d+]], type = "number" },
    }, symbols = {} }
    test.same(tokenizer.tokenize(syn, "(123)"),
      { "normal", "(", "number", "123", "normal", ")" })
    local stats = tokenizer.get_syntax_stats(syn)
    test.equal(stats.pattern_stats[1].unknown_starter, false)
    test.equal(stats.has_unknown_starters, false)
  end)
end)

test.describe("native tokenizer long lines", function()
  test.before_each(function(context)
    context.native = tokenizer.is_using_native()
    context.max_time = core.co_max_time
    tokenizer.set_use_native(true)
  end)

  test.after_each(function(context)
    core.co_max_time = context.max_time
    tokenizer.set_use_native(context.native)
  end)

  local function compare(syn, text)
    core.co_max_time = 3600
    tokenizer.set_use_native(false)
    local expected, expected_state = tokenizer.tokenize(syn, text)
    tokenizer.set_use_native(true)
    local tokens, state, resume = tokenizer.tokenize(syn, text)
    test.same(tokens, expected)
    test.equal(state, expected_state)
    test.is_nil(resume)
  end

  test.test("byte offsets preserve Unicode captures and frontier context", function()
    local syn = { patterns = {
      { pattern = "%f[%a]word()%s+()next", type = { "keyword", "normal", "keyword2" } },
      { pattern = "%f[%a]word", type = "keyword" },
      { pattern = "xword", type = "symbol" },
      { pattern = { "«", "»", "\\" }, type = "string" },
      { regex = [[\d+()\s*()$]], type = { "number", "normal", "normal" } },
    }, symbols = {} }
    compare(syn, string.rep("é🙂 xword word next «内容\\»末» ", 100) .. "42  ")
  end)

  test.test("regex lookahead and anchors see the full line", function()
    local syn = { patterns = {
      { regex = [[x(?=.{256}END)]], type = "keyword" },
      { regex = [[\d+$]], type = "number" },
      { pattern = ".", type = "normal" },
    }, symbols = {} }
    compare(syn, "éx" .. string.rep("a", 256) .. "END123 tail456")
  end)

  test.test("empty closing matches retain the boundary after the last character", function()
    for _, matcher in ipairs { "pattern", "regex" } do
      local syn = { patterns = {
        { [matcher] = { "<", "$" }, type = "string" },
      }, symbols = {} }
      for _, text in ipairs { "<abc", "<é🙂内容" } do
        compare(syn, text)
        local tokens, state = tokenizer.tokenize(syn, text)
        test.same(tokens, { "string", text })
        test.equal(state, string.char(0))
      end
    end
  end)

  test.test("invalid UTF-8 keeps checked regex matching", function()
    local syn = { patterns = {
      { regex = [[\d+]], type = "number" },
    }, symbols = {} }
    for _, invalid in ipairs {
      "\255", "\128", "\192\175", "\237\160\128", "\244\144\128\128", "\226\130",
    } do
      local tokens = tokenizer.tokenize(syn, "123" .. invalid)
      test.same(tokens, { "normal", "123" .. invalid })
    end
    compare(syn, "é🙂 123 中 456")
  end)

  -- Seed a legacy resume to force a deterministic yield after a known prefix,
  -- without depending on the native clock's resolution or machine speed.
  local function pending(syn, prefix, tail)
    core.co_max_time = 3600
    local tokens, state = tokenizer.tokenize(syn, prefix)
    local text = prefix .. tail
    core.co_max_time = -1
    local _, _, resume = tokenizer.tokenize(syn, text, nil, {
      res = tokens, i = prefix:ulen() + 1, state = state,
    })
    test.type(resume, "table")
    return text, resume
  end

  local function finish(syn, text, resume)
    core.co_max_time = 3600
    local tokens, state, next_resume = tokenizer.tokenize(syn, text, nil, resume)
    local expected, expected_state = tokenizer.tokenize(syn, text)
    test.same(tokens, expected)
    test.equal(state, expected_state)
    test.is_nil(next_resume)
    return tokens
  end

  test.test("cached resumes retain token prefixes and merge the last span", function()
    local syn = { patterns = {
      { pattern = "%d+", type = "number" },
      { pattern = "%a+", type = "symbol" },
    }, symbols = {} }
    for _, prefix in ipairs { "é🙂 abc 12", "é🙂 abc ", "é🙂 abc!" } do
      local text, resume = pending(syn, prefix, string.rep("123 abc! ", 100))
      local previous = resume.res
      local _, _, next_resume = tokenizer.tokenize(syn, text, nil, resume)
      test.equal(next_resume.res, previous)
      finish(syn, text, next_resume)
    end
  end)

  test.test("cached indexes survive interleaved lines, collection and cache clearing", function()
    local syn = { patterns = {
      { pattern = { '"', '"', "\\" }, type = "string" },
      { regex = [[\d+]], type = "number" },
    }, symbols = {} }
    local text1, resume1 = pending(syn, "é🙂 12\"open", string.rep("inside ", 100) .. '\" 34')
    local text2, resume2 = pending(syn, "中 56", string.rep(" 78", 200))
    collectgarbage("collect")
    tokenizer.clear_native_cache(syn)
    finish(syn, text2, resume2)
    finish(syn, text1, resume1)
  end)

  test.test("repeated time-sliced calls agree with uninterrupted tokenization", function()
    local syn = { patterns = {
      { regex = [[\d+]], type = "number" },
      { pattern = "%a+", type = "symbol" },
    }, symbols = {} }
    local text = "é🙂 " .. string.rep("123+abc! ", 5000)
    core.co_max_time = 3600
    local expected, expected_state = tokenizer.tokenize(syn, text)
    core.co_max_time = 0.001
    local tokens, state, resume
    local calls = 0
    repeat
      tokens, state, resume = tokenizer.tokenize(syn, text, state, resume)
      calls = calls + 1
      test.ok(calls < 5000, "tokenization must finish despite time slicing")
      if resume then collectgarbage("collect") end
    until not resume
    test.same(tokens, expected)
    test.equal(state, expected_state)
  end)

  test.test("legacy and changed resumes safely fall back to importing tokens", function()
    local syn = { patterns = {
      { regex = [[\d+]], type = "number" },
      { pattern = "%a+", type = "symbol" },
    }, symbols = {} }
    for _, mode in ipairs { "legacy", "text", "tokens", "position" } do
      local text, resume = pending(syn, "é 123!", string.rep("456 abc! ", 100))
      if mode == "legacy" then resume._native = nil end
      if mode == "text" then text = text:gsub("456", "789") end
      if mode == "tokens" then
        local copy = {}
        for i, value in ipairs(resume.res) do copy[i] = value end
        resume.res = copy
      end
      if mode == "position" then
        resume.i = resume.i + 1
        -- Supply the corresponding completed prefix for this new position.
        resume.res = tokenizer.tokenize(syn, text:usub(1, resume.i - 1))
      end
      finish(syn, text, resume)
    end
  end)
end)
