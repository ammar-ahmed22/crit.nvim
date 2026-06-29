# crit.nvim

Review crit sessions inside neovim. `crit.nvim` is a thin Lua wrapper around
the [`crit`](https://github.com/ammar-ahmed22/crit) CLI plus
[`echasnovski/mini.diff`](https://github.com/echasnovski/mini.diff), which
renders the diff **inline in a single window** (green adds / red deletes drawn
directly over the real file buffer — full syntax highlighting, whole file with
unchanged regions folded), not side-by-side.

The agent starts a session (`crit session start`), tells you the id, and you
review it without leaving your editor:

```vim
:CritAttach crit-7f3a2c    " inline diff opens in a new tab (file picker + diff)
:CritComment               " in visual mode: comment on the selection
:CritEdit                  " edit the comment under the cursor
:CritDelete                " delete the comment under the cursor
:CritList                  " quickfix-style list of every comment
:CritSubmit                " finalise; sends review.json back to the agent
```

## Requirements

- neovim 0.10+
- The `crit` binary on `$PATH` (`go install github.com/ammar-ahmed22/crit@latest`)
- [`echasnovski/mini.diff`](https://github.com/echasnovski/mini.diff)

Run `:CritDoctor` after installation to verify both are wired up. The
in-memory call log lives in `:CritLog` and is useful when filing bugs.

## Install

### packer.nvim

```lua
use {
  "ammar-ahmed22/crit.nvim",
  requires = { "echasnovski/mini.diff" },
  config = function() require("crit").setup({}) end,
}
```

### lazy.nvim

```lua
{
  "ammar-ahmed22/crit.nvim",
  dependencies = { "echasnovski/mini.diff" },
  opts = {},
}
```

### vim-plug

```vim
Plug 'echasnovski/mini.diff'
Plug 'ammar-ahmed22/crit.nvim'
" ...then in init.lua:
lua require('crit').setup({})
```

`mini.diff` does not need to be configured separately — crit.nvim drives it per
buffer and leaves your own `require('mini.diff').setup(...)` (if any) untouched.

## Commands

All commands start with `:Crit` so they are easy to remap. None of them have
default keybindings — wire up whatever you like in your own config.

| Command | Behaviour |
|---|---|
| `:CritAttach <id>` | Load a session by id. cd's into its repo, opens the inline diff view (file picker + unified diff) in a new tab against its scope, paints existing draft comments as signs + virtual text. Warns if HEAD has drifted since the snapshot was taken. |
| `:CritDetach` | Clear the in-memory state and signs, and close the diff view tab. |
| `:CritComment` | Add a comment on the current line, or — with a range, e.g. `:'<,'>CritComment` — on the selected lines. The current buffer must be a crit diff buffer. Comments anchor to the new side of the diff. |
| `:CritEdit` | Edit the comment under the cursor. If multiple comments overlap the line, pick one via `vim.ui.select`. |
| `:CritDelete` | Delete the comment under the cursor (with confirm). |
| `:CritList` | Populate the quickfix list with every draft comment. `<CR>` jumps to a comment in the inline diff view. |
| `:CritSubmit` | Open the submit window. Pick a verdict (`a`/`r`/`m`), type a summary, then `:wq` (or `<C-s>`) to submit. Detaches on success. |
| `:CritShow` | Echo session metadata (id, status, scope, instructions). |
| `:CritOpen` | Open the upstream Bubble Tea TUI for the attached session in a terminal split. |
| `:CritDoctor` | Print dependency status. |
| `:CritLog` | Open the crit.nvim call log buffer. |

### Comment editor

The editor behaves like a normal file buffer:

| Command / Key | Action |
|---|---|
| `:w` | stage the body (window stays open) |
| `:wq` / `:x` / `ZZ` | save and submit, then close |
| `<C-s>` | save and submit immediately |
| `<C-t>` | cycle kind: `comment` → `question` → `nit` → `blocking` |
| `:q` / `q` / `<Esc>` | quit; submits if you ran `:w` first, otherwise cancels |

### Submit window

| Command / Key | Action |
|---|---|
| `a` / `r` / `m` | verdict: approve / request_changes / comment |
| `:w` | stage the summary (window stays open) |
| `:wq` / `:x` / `ZZ` | save and submit, then close |
| `<C-s>` | save and submit immediately |
| `:q` / `q` / `<Esc>` | quit; submits if you ran `:w` first, otherwise cancels |

## Configuration

The defaults in `lua/crit/config.lua`:

```lua
require("crit").setup({
  bin = "crit",                  -- path to the crit binary
  sessions_dir = nil,            -- passes through to --sessions-dir if set
  sign_group = "CritComments",
  signs = {
    comment  = { text = "●", hl = "DiagnosticInfo"  },
    question = { text = "?", hl = "DiagnosticHint"  },
    nit      = { text = "~", hl = "DiagnosticHint"  },
    blocking = { text = "!", hl = "DiagnosticError" },
  },
  virt_text = {
    enabled = true,
    prefix = "▌ ",
    max_chars = 60,
    hl = "Comment",
  },
  view = {
    picker_width = 40,      -- columns for the file-picker sidebar
    fold_unchanged = true,  -- fold runs of unchanged lines away from hunks
    context = 3,            -- lines kept around each hunk when folding
  },
  warn_on_head_drift = true,
})
```

### The inline diff view

`:CritAttach` opens a dedicated tab with a file picker on the left and a single
inline-diff buffer on the right:

```
┌────────────────────┬──────────────────────────────────────┐
│ M app.go      (2)   │  5   // Greet prints a friendly...    │
│ A new.go            │  6   func Greet(name string) {        │
│ D del.txt           │  7 ~ fmt.Println("hi there " + name)  │  ← change
│ M big.txt           │  8 + fmt.Println("welcome")           │  ← add
│                     │  9   }                                │
└────────────────────┴──────────────────────────────────────┘
```

- The picker shows each changed file with a status marker (`M`/`A`/`D`/`R`) and
  a live count of draft comments. `<CR>` opens the file in the diff window.
- The diff is drawn by `mini.diff`'s overlay over the **real file buffer**, so
  you keep full per-language **syntax highlighting**. Unchanged regions away
  from a hunk are **folded** (configurable via `view.fold_unchanged` /
  `view.context`).
- Comments anchor to the **new** side of the diff (the line numbers in the
  buffer). Old-side (deleted-line) commenting is not wired up yet.

## Typical agent flow

1. Coding agent makes changes.
2. Agent runs `crit session start --base main --title "..."` and tells you the
   id.
3. In nvim: `:CritAttach crit-7f3a2c`. The inline diff opens in a new tab.
4. Pick a file in the left picker (`<CR>`), walk the diff. `V`+`:CritComment`
   to comment on a range. `:CritEdit` / `:CritDelete` as needed.
5. `:CritSubmit`. Pick verdict, type summary, `:wq`.
6. Agent's `crit session wait` returns the `review.json` and proceeds.

## Status

Early. The plugin is built on the `crit` headless CLI surface
(`crit session draft show`, `crit session comment add|edit|delete`,
`crit session submit`) — those are documented in
[`crit/AGENT.md`](https://github.com/ammar-ahmed22/crit/blob/main/AGENT.md#headless-human-surface-editor-integrations)
and stable. Bugs and feature requests welcome.

## License

MIT.
