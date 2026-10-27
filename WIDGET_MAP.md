# Widget library map

Mapped on 2026-10-27 from the checkout the editor actually ships:
`subprojects/widget` at `c11e78c` plus an untracked caret edit in
`textbox.lua`. `amer-layer` pins `3047f9a`; the only difference is
`searchreplacelist.lua` (`display_path` support). Upstream pragtical master
pins `bb06c23`. Line counts are from the shipped checkout.

## How it gets into the build

- `meson.build:440-442` pulls in the `widget` subproject unless
  `data/widget/init.lua` already exists in the repo.
- `subprojects/widget.wrap` gives the repo URL
  (`https://github.com/pragtical/widget.git`), the pinned commit and
  `patch_directory = widget`.
- `subprojects/packagefiles/widget/meson.build` holds the install rules Meson
  overlays onto the checkout. It copies everything into `data/widget/`.
- Meson does not move an existing checkout when the pin changes. After changing
  `widget.wrap`, update `subprojects/widget` by hand (or delete it and let
  Meson re-fetch it), or the build keeps shipping the old revision.

## Class hierarchy

Everything descends from `Widget`, which extends core's `View`. It's defined in
`init.lua`, the one big file.

```
core.View
└─ Widget                      init.lua            1693  base: layout, mouse/hover, focus, scrolling, animations, tooltips, popups
   ├─ Basic controls
   │  ├─ Button                button.lua           162
   │  ├─ CheckBox              checkbox.lua         139
   │  ├─ Toggle                toggle.lua           140  switch + label
   │  ├─ ToggleButton          togglebutton.lua     204
   │  ├─ Label                 label.lua            238  plain or styled text
   │  ├─ Line                  line.lua              67  separator
   │  └─ ProgressBar           progressbar.lua       95
   ├─ Text input
   │  ├─ TextBox               textbox.lua          412  single-line input (see below)
   │  └─ NumberBox             numberbox.lua        221  TextBox + up/down buttons
   ├─ Lists and trees
   │  ├─ ListBox               listbox.lua          987  multi-column rows
   │  ├─ SelectBox             selectbox.lua        308  dropdown built on ListBox
   │  ├─ TreeList              treelist.lua         709
   │  ├─ SearchReplaceList     searchreplacelist.lua 694  file → line → match results with checkboxes
   │  ├─ ItemsList             itemslist.lua        164  editable string list (ListBox + InputDialog)
   │  └─ FontsList             fontslist.lua        222  font list (ListBox + FontDialog)
   ├─ Layout
   │  ├─ Container             container.lua        186  plain container
   │  ├─ NoteBook              notebook.lua         190  tabs
   │  └─ FoldingBook           foldingbook.lua      237  collapsible sections
   ├─ Pickers
   │  ├─ FilePicker            filepicker.lua       415  path field + browse button
   │  └─ ColorPicker           colorpicker.lua      846  HSV/RGB picker with hex TextBox
   ├─ MessageBox               messagebox.lua       339  modal info/warn/error/question
   └─ Dialog                   dialog.lua           167  base for modal dialogs
      ├─ InputDialog           inputdialog.lua       86
      ├─ ColorPickerDialog     colorpickerdialog.lua 81
      ├─ FontDialog            fontdialog.lua       359
      └─ KeybindDialog         keybinddialog.lua    262

core.ScrollBar
└─ ScrollBar                   scrollbar.lua         33  widget-aware scrollbar, used by Widget

Support modules (not widgets)
   fonts/init.lua, fonts/cache.lua, fonts/info.lua   system font discovery and caching, used by FontDialog/FontsList
   examples/*.lua                                    demos: floating, listbox, messagebox, notebook, search
```

### Inside `textbox.lua`

`TextBox` (line 217) is a widget wrapped around a stripped-down editor. It has
three internal classes:

- `SingleLineDoc` extends core `Doc` and holds a single line.
- `SingleLineHighlighter` extends core `Highlighter`.
- `TextView` extends core `DocView` and has no gutter or line highlight.

Because of this, `TextBox` behavior partly comes from core `Doc`/`DocView` in
the main repo. The undo rewrite (`f26509d9`) runs inside every TextBox too.

**Untracked local edit:** `TextView:draw_caret` (around line 129) forces a thin
line cursor instead of the block cursor. Neither the widget repo nor
`amer-layer` tracks it; resetting or re-fetching `subprojects/widget` deletes
it.

## Which widgets each widget uses

| Widget | Pulls in |
|---|---|
| `Widget` (`init.lua`) | ScrollBar |
| Dialog | Button, Label |
| MessageBox | Button, Label |
| FilePicker | Button, Label |
| NumberBox | Button, TextBox |
| ColorPicker | TextBox |
| SelectBox | ListBox |
| ListBox | MessageBox |
| NoteBook, FoldingBook | Button |
| Toggle | Label |
| InputDialog | Dialog, Button, Label, TextBox |
| ColorPickerDialog | Dialog, Button, ColorPicker |
| KeybindDialog | Dialog, Button, Label, Line, ListBox, MessageBox |
| FontDialog | Dialog, Button, CheckBox, Label, Line, MessageBox, NumberBox, SelectBox, fonts |
| ItemsList | Button, InputDialog, ListBox, MessageBox |
| FontsList | Button, FontDialog, ListBox, MessageBox |

## Who uses them

### Core and bundled plugins (`amer-layer`)

| File | Widgets used |
|---|---|
| `data/core/emptyview.lua` | Widget, Button, Container, ListBox (the welcome screen is itself a Widget) |
| `data/plugins/projectsearch.lua` | Widget, Button, FilePicker, MessageBox, **SearchReplaceList**, TextBox, ToggleButton |
| `data/plugins/search_ui.lua` | Widget, Button, FilePicker, Label, Line, TextBox, ToggleButton |
| `data/plugins/settings.lua` | Button, ColorPicker, Container, FilePicker, FoldingBook, fonts, FontsList, ItemsList, KeybindDialog, Label, Line, ListBox, MessageBox, NoteBook, NumberBox, SelectBox, TextBox, Toggle |

The settings UI uses the most widgets by far, nearly the whole library.

### User plugins (`~\.local\pragtical\user\plugins\lsp`)

| File | Widgets used |
|---|---|
| `lsp/init.lua` | MessageBox |
| `lsp/ui/renamesymbol.lua` | Widget, Button, Label, Line, ListBox, MessageBox, **SearchReplaceList** |
| `lsp/ui/symbolresults.lua` | Widget, Label, Line, ListBox |
| `lsp/ui/symbolstree.lua` | Widget, SelectBox, TextBox, TreeList |

The LSP plugin is the only user of `TreeList`, and the only other user of
`SearchReplaceList` besides project search. Check it after any widget change.

**Unused by anything here:** ProgressBar, and ColorPickerDialog. Settings uses
ColorPicker directly instead.

## Upstream changes under consideration

Upstream widget commits after the `3047f9a` pin that are worth bringing over.
They apply cleanly onto the pin in this order, but haven't been built or tested
yet.

| Pick | What it does | Files | Who you'd test |
|---|---|---|---|
| `15575ca` | TextBox mouse selection: long inputs scroll while drag-selecting. Upstream paired it with an 8-line `data/core/rootview.lua` fix (`0ab98635`); take both. | `init.lua`, `textbox.lua`, `colorpicker.lua` | Everything; `textbox.lua` holds the caret edit, so expect a merge there |
| `e370096` | Clear hover when the pointer leaves nested widgets | `init.lua` | Everything; the main candidate is scrollbars inside settings and project search |
| `bb06c23` | Less update overhead (about 25% less idle CPU with Settings open, per upstream) | `init.lua`, `textbox.lua` | Everything; positioning of nested widgets when parents move |

All three touch `init.lua`, the base class every widget inherits. So test
broadly: settings UI, project search, search/replace, the welcome screen and the
LSP rename/symbol views.

Skipped: `c0defd8`, `270b912`, `09b4227`, `e05fd2c` (WidgetList feature),
`15a1acb` (needs core floating views from upstream's menus commit), `eb5519b`
(layout rework tied to upstream's UI-scaling changes), `e7e9878` (needs
main-repo `62b3659c`).
