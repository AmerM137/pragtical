# `amer-layer` versus mainline cherry-pick review

## OPEN: stale open documents after external edits (Windows)

Watching this after the 2026-08-02 merge; unresolved, not yet reproduced.

Symptom: an agent or external program modifies a file on disk and Pragtical
keeps showing a stale copy of it.

Owner module is `data/plugins/autoreload.lua` over `data/core/dirwatch.lua`
over `src/api/dirmonitor/win32.c`. This build auto-selects the `win32` backend.

Established by inspection:

- The native watcher never drives autoreload for open documents on Windows.
  `win32.c:75` reports mode `single`; in `dirwatch.lua:76` a *file* in single
  mode takes `return self:scan(path)` and is never natively watched. Separately,
  the single-mode dispatch at `dirwatch.lua:142-146` hands `common.dirname(id)`
  — a directory — to the callback, while `autoreload.lua:122` compares it to
  `doc.abs_filename`, a file, so that branch could never match anyway.
  Detection is therefore pure 1-second polling. On Linux/inotify the mode is
  `multiple`, the file is watched directly and the file path is delivered, which
  is why this presents as Windows-specific.
- The polling loop at `dirwatch.lua:176` compares only `modified`, never `size`.
  Windows `modified` is millisecond resolution (`system.c:762`), so a fast
  in-place rewrite can slip through.

Possibly already fixed: `3db2d047` (merged here) added a sweep over open
documents at `autoreload.lua:127-133` comparing modified **and** size. Retest
before investigating further.

If it still reproduces, next suspect is `autoreload.lua:40` — `doc_changed()`
returns false whenever `times[doc]` is nil, and `times[doc]` is populated only
by a deferred thread gated on a view already referencing the doc
(`autoreload.lua:147`), with no retry. A document that misses that window stays
permanently invisible to both the watcher and the sweep, which would fit the
intermittent behavior.

Ruled out: a reload prompt getting stranded with `deferred_reload` stuck true.
`force_focus` (`init.lua:1098`) blocks the active-view change that would discard
the prompt without running its callback.

---

Compared `amer-layer` with `upstream/master` on 2026-08-02, then **executed**
the cherry-picks on branch `amer-layer-sync` (branched from `amer-layer`).
The verdicts below reflect what actually applied, not just static inspection.

Decision: **code folding is rejected in its entirety.** No `codefold.lua`, no
`test_codefold.lua`, no `code_folding_disabled` flags, and none of the
`DocView:ensure_line_visible` / visual-line-model plumbing that folding
introduced.

Status meanings:

- `DONE` — cherry-picked onto `amer-layer-sync`.
- `PARTIAL` — cherry-picked with the code-folding portion stripped.
- `REJECT` — intentionally excluded: code folding, or release-only metadata.
- `ALREADY PRESENT` — equivalent patch already in `amer-layer`.
- `N/A` — only meaningful inside fold infrastructure this branch does not have.

## Corrections to the first pass

Three entries the earlier review marked `OK` were wrong, and two `REJECT`
entries were partly salvageable:

- `d61d6bf6`, `43251780`, `08ed2c34` — **already present**. `amer-layer` carries
  them as `d74bbe53`, `bbf3e3aa`, and `12595476`. Cherry-picking `43251780` and
  `08ed2c34` produces an empty diff; `markdownview.lua` and `tests/http.lua` are
  already byte-identical to upstream at those commits.
- `1d6495e8` — **not applicable**. The fix adds a `self.doc.lines[line]` guard to
  the visual-row draw loop in `DocView:draw()`. `amer-layer` still uses the plain
  `for i = minline, maxline` loop, which cannot produce a stale row, so there is
  nothing to guard.
- `1156b8d8` — **reject stands, for a better reason**. Its `docview.lua` half is
  not incidentally fold-adjacent; it *is* the fold visual-line model
  (`get_hidden_lines`, `invalidate_visual_lines`, `rebuild_visual_lines`). The
  `linewrapping.lua` half is written against that model. Porting the long-line
  rebuild optimization to this branch would be a rewrite, not a cherry-pick.
- `543db092` — **partially salvaged**. The DiffView scrollbar-marker fix is
  independent; only two `code_folding_disabled = true` assignments were fold
  related. Applied as `213731b4` with those two lines dropped.

## Commit review

| Status | Commit | Brief summary |
|---|---|---|
| ALREADY PRESENT | `d61d6bf6` | Render Markdown frontmatter more legibly. |
| ALREADY PRESENT | `a566e947` | Improve DocView rendering for long lines. |
| ALREADY PRESENT | `509c53ba` | Synchronize line wrapping with DocView rendering. |
| ALREADY PRESENT | `18a845b3` | Optimize native tokenizer matching on long lines. |
| ALREADY PRESENT | `ce23fcbd` | Improve naming of tests for nested directories. |
| ALREADY PRESENT | `57b8f0ea` | Add popular-language code-block patterns to Markdown highlighting. |
| ALREADY PRESENT | `b6e8f7f6` | Return byte counts from TCP writes. |
| ALREADY PRESENT | `fb3f26c7` | Update GitHub Actions workflow dependencies. |
| ALREADY PRESENT | `43251780` | Parse large Markdown views asynchronously. |
| REJECT | `80f99dc8` | Code-folding system, DocView support, plugin, and tests. |
| REJECT | `23dbc145` | v3.11.0 release metadata. |
| ALREADY PRESENT | `3564d0fc` | Avoid rebuilding hidden status items. |
| ALREADY PRESENT | `dab49b81` | Handle partial process writes correctly. |
| ALREADY PRESENT | `08ed2c34` | Avoid HTTP test-port file races. |
| REJECT | `2ddfccd4` | Polish code-fold markers and related tests. |
| ALREADY PRESENT | `39fa6996` | Welcome screen's recent-project menu. |
| REJECT | `1156b8d8` | Line-wrapping rebuild optimization, built on the fold visual-line model. |
| DONE | `ec93d50a` | Improve AppImage packaging. |
| DONE | `21ef76c0` | Embed version metadata in AppImages. |
| ALREADY PRESENT | `500a513d` | Use `highlighter:each_token` while drawing line text. |
| REJECT | `ca5a2f43` | v3.11.1 release metadata. |
| ALREADY PRESENT | `764185af` | Resolve find-file paths against the open project root. |
| ALREADY PRESENT | `8c58d27d` | Fix JavaScript regex literals after a ternary colon. |
| N/A | `1d6495e8` | Skip stale visual rows during drawing (fold-only draw path). |
| REJECT | `6ae26135` | v3.11.2 release metadata. |
| DONE | `6ded8c28` | Preserve startup scale through application restarts. |
| DONE | `83569ca0` | Copy LuaJIT modules for local runs. |
| REJECT | `efbd2c23` | Require project trust before loading project modules. Dropped by request — see below. |
| DONE | `f7194368` | Skip network Lua files when networking is disabled. |
| DONE | `2a7481da` | Disable remote Markdown images when networking is disabled. |
| DONE | `a3c104ba` | Load only Lua files when loading plugins. |
| DONE | `cc42d872` | Display search totals incrementally. |
| DONE | `2d6b3aa3` | Show details for directory plugins. |
| REJECT | `0d82fd9c` | Clear code-fold hover state when the mouse leaves. |
| PARTIAL | `543db092` | DiffView scrollbar markers kept; fold-disable dropped. |
| DONE | `d72e9456` | Fix negative offsets in regex handling. |
| DONE | `d4c135d3` | Use the native PPM build in Meson. |
| DONE | `4959cb4d` | Fix EmptyView plugin-button detection. |
| DONE | `5c53a135` | Remove rolling-release artifacts. |
| DONE | `318ea00e` | Modularize the renderer and add the SDL GPU backend. |
| REJECT | `a2091db7` | v3.12.0 release metadata. |
| DONE | `ecc17c58` | Prefer low-power SDL GPU devices. |
| DONE | `5f48925f` | Expose renderer information on Windows. |
| DONE | `04c69472` | Fix window-color readback with SDL GPU. |
| DONE | `c35391bc` | Limit exported FFI symbols on Linux. |
| REJECT | `36ec7dcd` | v3.12.1 release metadata. |
| DONE | `9b681762` | Tolerate degenerate SDL GPU polygons in triangulation. |
| DONE | `b6e0a38e` | Fix degenerate SDL GPU polygon handling. |
| DONE | `44e33091` | Speed up dense SDL GPU rectangle replay. |
| DONE | `b19f6b97` | Fix Unicode case-insensitive search. |
| DONE | `3db2d047` | Improve directory-monitor reliability. |
| DONE | `41b9179d` | Fix LuaJIT 32-bit x86 startup crashes. |
| DONE | `c3e189f4` | Allow `system.setenv` to unset values. |
| REJECT | `fcd2aec1` | v3.12.2 release metadata. |
| DONE | `35d49aff` | Add multi-project support to Project Search. |
| REJECT | `11e8e7bd` | Fix code-fold gutter sizing. |
| REJECT | `97e8ca3c` | Split code-fold toggle commands. |
| REJECT | `c1e563fb` | Relax a code-fold keybinding test. |
| DONE | `596d660e` | Add syntax colors. |
| DONE | `6c07215a` | Fix keybinding reset behavior when defaults are absent. |
| DONE | `393b6489` | Add `autocomplete:open` for on-demand suggestions. |
| REJECT | `43121eef` | v3.12.3 release metadata. |
| DONE | `c2a9982c` | Improve `run_step` error diagnostics. |
| DONE | `4d0207b4` | Fix SDL GPU subpixel text on light backgrounds. |
| DONE | `3a60bd7a` | Reorganize renderer files and names. |
| DONE | `8af37f7a` | Add controls to the Project Search view. |
| REJECT | `1783633f` | v3.12.4 release metadata. |
| DONE | `a746d41a` | Fix SDL3 probes with CMake 4. |

## Conflicts resolved

Only three of the 36 picks conflicted, and none required judgement about
folding beyond dropping it:

- `318ea00e` — `scripts/lua/tests/linewrapping.lua`. Upstream's copy of this file
  carries fold-era test cases. The commit's own contribution is a
  `dofile_from_source()` helper that resolves plugin paths against the source
  root. `amer-layer`'s copy of the file has no `dofile` calls at all, so our
  version was kept unchanged and nothing was lost.
- `c35391bc` — `meson_options.txt`. `amer-layer` intentionally keeps the `repl`
  option and defaults `repl_history` to `false` (from `ee03dcfb`). Those were
  preserved; only the new `export_all_symbols` option was added.
- `543db092` — resolved by hand as described above.

## Deliberately unchanged

- `meson.build` version stays at `3.11.1` — every release-metadata commit was
  rejected, so the branch does not track upstream's `3.12.4`.
- `subprojects/plugins.wrap` stays pinned at `a88f8df`. Upstream bumps it inside
  `80f99dc8` and the release commits; taking the bump would pull in
  fold-aware plugin revisions.

## Dropped after the fact: project trust (`efbd2c23`)

Initially cherry-picked, then removed by request via
`git rebase --onto 2930f308^ 2930f308`. The 34 following commits replayed with
no conflicts.

Upstream gates `.pragtical_project.lua` behind an explicit trust prompt, since
that file is otherwise executed as arbitrary Lua whenever a project is opened.
This repository ships its own `.pragtical_project.lua`, so the prompt fired on
every launch. The feature has no `config` switch, so dropping the commit was
the only way to disable it.

Removing it restores the previous behavior in full:

- `Project Module` is loaded unconditionally again at priority `-1` in
  `core.load_plugins()`.
- `settings.lua` `reload_user_modules` reloads the project module again.
- `autorestart.lua` auto-reloads on saving `.pragtical_project.lua` again.
- `scripts/lua/tests/project_trust.lua` is gone.

Worth remembering that the security tradeoff is real: opening an untrusted
repository that contains a `.pragtical_project.lua` will execute it.

## Verification status

- Fold audit is clean: no `codefold`, `code_folding`, or `ensure_line_visible`
  references anywhere in tracked source.
- Trust audit is clean: no `trusted_project`, `is_project_trusted`, or
  `prompt_project_trust` references anywhere in tracked source.
- **Compiles.** Confirmed by the user with `build.bat`, including the
  renderer/SDL GPU group. (Note: verification predates the `efbd2c23` drop,
  which only removed Lua.)

## Remaining opportunity

The long-line line-wrapping rebuild optimization from `1156b8d8` is real value
that this branch does not get. Capturing it means reimplementing the
optimization against `amer-layer`'s non-fold `linewrapping.lua`, as new work
rather than a cherry-pick.
