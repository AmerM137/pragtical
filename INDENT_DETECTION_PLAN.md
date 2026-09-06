# Indent detection: bugs, missing layer, and a plan

Status: **investigation complete, nothing implemented.**
Branch: `amer-layer`. Line numbers verified against this tree (`data/` is byte-identical
to the installed `~/.local/pragtical/data`, so they hold for both).

---

## TL;DR

`detectindent` silently discards most of a file whenever a comment contains an
apostrophe, because it infers comment delimiters by scraping the syntax's token
patterns and cannot tell a string rule from a comment rule. Separately, there is
no per-language indent setting, so any detection failure falls straight through
to the single global `config.indent_size`.

Fix is three small changes across three files, with a **net negative** line count
(~230 of `detectindent.lua`'s 420 lines are the scanning/scoring machinery).

---

## Background: how indent size is decided today

There is no per-language indent setting anywhere. Syntax tables have no indent
field, and nothing in `core.syntax` looks for one. Three layers decide:

1. **Global default** — `data/core/config.lua:227` `config.indent_size = 2`,
   `:233` `config.tab_type = "soft"`.
2. **Per-document detection** — the `detectindent` plugin scans up to ~150 lines
   of each opened file and writes `doc.indent_info`. Triggered from
   `DocView:draw` (`detectindent.lua:307`), once per view, and only for docs with
   a visible view.
3. **Fallback** — `Doc:get_indent_info()` (`data/core/doc/init.lua:263`) returns
   `config.tab_type, config.indent_size, false` whenever `indent_info` is unset.
   `detectindent`'s own `update_cache` (`detectindent.lua:288`) *also* falls back
   to the same globals when its confidence score is `< 2`.

Detection works on most real files. Measured with the real
`detect_indent_stat` over this tree:

```
user/*.lua     ( 68 files)  detected 2: 49,  detected 4: 5,  fallback: 14
data/**/*.lua  (253 files)  detected 2: 155, detected 3: 3, detected 4: 2, fallback: 93
```

and over a C++/CUDA codebase (`~/prog/ninfer`, 4-space):

```
arena.cu                  -> soft 4 (score 85)
bf16_attn_input_decode.cu -> soft 4 (score 35)
engine.h                  -> soft 4 (score 51)
CMakeLists.txt            -> soft 2 (score 65)
```

The fallback bucket is the problem area, and it is larger than it should be.

---

## Bug 1 — string delimiters are treated as comment delimiters

`get_comment_patterns` (`data/plugins/detectindent.lua:82`) builds its comment
list by walking `syntax.patterns`, i.e. the *tokenizer* rules. Those include
string and char rules, and the function has no way to distinguish them from
comment rules. For Lua it derives, among others:

```
[10] start="\""   end="\""
[12] start="'"    end="'"
[14] start="%[%[" end="%]%]"
```

`get_non_empty_lines` (`:186`) then runs a line-oriented state machine over
these. A line containing an odd number of quotes opens a "comment" that never
closes, and every subsequent line is discarded.

### Repro

`~/.local/pragtical/user/plugins/tabless_switcher.lua` (any file with an
apostrophe in a comment will do). Line 9 reads:

> `  remaining document instead of falling through to Pragtical's adjacent-tab`

One apostrophe. Result:

```
yielded 5 of 525 lines; 0 of them indented
optimal_indent_from_stat -> indent=nil score=0
detect_indent_stat       -> soft 2 score=0      (i.e. pure config fallback)
```

The file has 84 indented lines inside the detector's own 150-line window. None
are seen. It is silently classified as "no indentation information" and inherits
the global default.

This is language-independent — any prose comment with an apostrophe, or an
unbalanced quote of any kind, triggers it.

### Why it looked benign

A first pass over the fallback bucket reads as "flat files with no indentation
to preserve" (the colour themes genuinely are: one `style.syntax[...] = {...}`
per line at column 0). `tabless_switcher.lua` is the counterexample that shows
the bucket also contains normally-indented files.

---

## Bug 2 — single-line comment matching is unanchored

`detectindent.lua:210`:

```lua
elseif line:find(comment[2]) then
  is_comment = true
```

Unanchored. Any line *containing* `--` / `//` anywhere is dropped as a comment:
`i--`, `http://...`, a `--` inside a string literal. The regex branch immediately
below (`:233`) correctly uses `regex.ANCHORED`; the Lua-pattern branch does not.
Straight inconsistency between the two paths.

---

## Gap 3 — there is no per-language indent layer

Both fallback sites (`doc/init.lua:263` and `detectindent.lua:292-294`) read the
*global* `config.indent_size`. Consequences:

- Every new/empty buffer of every language gets the same size, because an empty
  buffer has nothing to detect. Verified: `new empty newfile.lua -> soft 4
  (score 0) FALLBACK` when the global is set to 4.
- There is no way to express "4 for C-family, 2 for Lua" in configuration.

The only workaround from userland is to hook `Doc:reset_syntax` and write
`indent_info = { size = 4, confirmed = true }`. `confirmed = true` is required to
stop `detectindent` overwriting it on first draw — which also disables detection
for those files entirely, so a genuinely 2-space third-party C++ file gets edited
at 4. That override currently lives in `~/.local/pragtical/user/init.lua` under
the `INDENTATION` header and should be deleted once this lands.

---

## Plan

Three changes. Each is independently committable; one commit per item to keep
cherry-picking upstream clean.

### 1. Add the missing layer (core, ~12 lines)

`data/core/config.lua`, after `:233`:

```lua
---Per-syntax indent overrides, keyed by syntax name.
---e.g. config.indent_by_syntax["CUDA"] = { type = "soft", size = 4 }
config.indent_by_syntax = {}
```

`data/core/doc/init.lua`, new resolver next to `get_indent_info` (`:263`):

```lua
function Doc:get_default_indent_info()
  local s = self.syntax
  local o = s and (config.indent_by_syntax[s.name] or s.indent)
  return (o and o.type) or config.tab_type,
         (o and o.size) or config.indent_size
end
```

and `get_indent_info` uses those two values in place of its `config.*` reads.

Precedence becomes explicit and layered:

> explicit per-doc setting → confident detection → language default → global

The `s.indent` arm lets a language plugin ship its own convention by declaring
`indent = { size = 4 }` in its syntax table. `syntax.add` passes unknown fields
through untouched, so this needs no `core.syntax` change.

### 2. Make detection failure land on the language default (1 line)

`detectindent.lua:292-294`, inside `update_cache`, replace

```lua
type = config.tab_type
size = config.indent_size
```

with

```lua
type, size = doc:get_default_indent_info()
```

This is what makes item 1 compose. It yields the semantics that are currently
unreachable from userland: **detection still wins when confident; the language
default only fills the gap.**

### 3. Replace the comment scraper with the declared fields (~-180 lines)

Delete `get_comment_patterns` (`:82-184`), `escape_comment_tokens`, and
`comments_cache`. Rewrite `get_non_empty_lines` (`:186-259`) to use only the
syntax's *declared* `comment` and `block_comment` fields — which exist for
exactly this purpose — with plain (non-pattern) matching via
`find(..., 1, true)`, anchored at `^%s*`.

Kills Bug 1 and Bug 2 together.

Coverage check — 17 of 21 bundled language plugins declare `comment =`. The four
that don't:

```
language_css.lua  language_html.lua  language_md.lua  language_xml.lua
```

These declare `block_comment` or genuinely have no line comments. "No stripping"
is a safe degradation for indent detection anyway: comment stripping only guards
against `*`-aligned block comment bodies skewing the stats.

### 4. Optional — simplify the metric

`optimal_indent_from_stat` (`:25-80`) scores *absolute* indent widths with an
O(n²) divisibility heuristic. The conventional approach is the mode of positive
deltas between consecutive code lines:

```lua
-- ~15 lines: for each code line, d = width - prev_width; if d > 0 then
-- deltas[d] = deltas[d] + 1 end; pick the most frequent d, score = its count.
```

More accurate on files that mix alignment with indentation (continuation lines
produce scattered large deltas, so the mode still wins), and `score` acquires an
obvious meaning: how many times that step was observed.

Keep this as its own commit — it is the only change that could regress on a file
type the current heuristic happens to handle, so it should be revertable alone.

---

## Resulting user config

The `Doc:reset_syntax` override in `user/init.lua` gets deleted and becomes:

```lua
config.indent_by_syntax["C"]    = { size = 4 }
config.indent_by_syntax["C++"]  = { size = 4 }
config.indent_by_syntax["CUDA"] = { size = 4 }
```

Behaviour after:

| case | before | after |
|---|---|---|
| new `.cu` file | 2 | 4 |
| new `.lua` file | 2 | 2 |
| existing 4-space `.cu` | 4 (detected) | 4 (detected) |
| existing 2-space third-party `.cpp` | 4 (forced by the hook) | 2 (detected) |
| `tabless_switcher.lua` | 2 (accidental — fallback) | 2 (actually detected) |

---

## Sequencing / upstreamability

- **Items 1+2** are additive and non-breaking. Good standalone upstream PR; also
  the pair that unblocks the C-family-at-4 use case.
- **Item 3** is a bugfix PR on its own, with `tabless_switcher.lua` as the repro.
  Arguably the more important one for upstream, since it silently degrades
  detection for every language.
- **Item 4** is optional polish.

Items 1+2 and item 3 are independent and can go in either order.

---

## Notes for picking this back up

Everything above was measured headless with `pragtical run <script.lua>`, which
gives a full runtime with `DATADIR` / `USERDIR` set. Gotchas:

- **`pragtical run` also loads `user/init.lua`.** It is registered as the "User
  Module" at priority `-2` in `core.load_plugins` (`data/core/init.lua:784`), so
  it runs before every other plugin, and any userland monkey-patching is already
  installed by the time your script starts. Confirm with
  `require("core.style").caret_width` (init.lua sets 4; the default is 2).

  This will silently contaminate measurements. The `Doc:reset_syntax` override
  currently in `user/init.lua` pins C/C++/CUDA docs to `size = 4,
  confirmed = true` at construction, so a freshly created `Doc("k.cu", ...)`
  reads back as `soft 4 confirmed=true` before you have set anything. To get the
  true baseline, clear `doc.indent_info = nil` after constructing the doc — that
  restores `soft 2 confirmed=false`. Re-verify any result that looks like it
  already matches the outcome you were hoping to produce.
- `detect_indent_stat`, `get_non_empty_lines`, `get_comment_patterns` and
  `optimal_indent_from_stat` are all file-locals. To exercise the real code
  rather than a copy, read `detectindent.lua` as a string, append
  `return { detect = detect_indent_stat, ... }`, and `load()` it.
- Detection normally runs from `DocView:draw`, so it cannot be triggered
  headless; call `detect_indent_stat` directly on a stub
  `{ lines = <array of "line\n">, syntax = syntax.get(path) }`, and replicate
  `update_cache`'s `score < 2` threshold by hand.
- `require "plugins.<name>"` misbehaves after a manual `load()` of a plugin
  chunk in the same script (`package.path` ends up without the `.lua`
  searchers). Use `dofile` with an absolute path, or do the requires first.
