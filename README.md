# crit.nvim

Review crit sessions inside neovim. `crit.nvim` is a thin Lua wrapper around
the [`crit`](https://github.com/ammar-ahmed22/crit) CLI plus
[`sindrets/diffview.nvim`](https://github.com/sindrets/diffview.nvim) for the
diff itself.

The agent starts a session (`crit session start`), tells you the id, and you
review it without leaving your editor:

```vim
:CritAttach crit-7f3a2c    " Diffview opens on the session's scope
:CritComment               " in visual mode: comment on the selection
:CritEdit                  " edit the comment under the cursor
:CritDelete                " delete the comment under the cursor
:CritList                  " quickfix-style list of every comment
:CritSubmit                " finalise; sends review.json back to the agent
```

## Requirements

- neovim 0.10+
- The `crit` binary on `$PATH` (`go install github.com/ammar-ahmed22/crit@latest`)
- [`sindrets/diffview.nvim`](https://github.com/sindrets/diffview.nvim)

Run `:CritDoctor` after installation to verify both are wired up. The
in-memory call log lives in `:CritLog` and is useful when filing bugs.

## Install

### packer.nvim

```lua
use {
  "ammar-ahmed22/crit.nvim",
  requires = { "sindrets/diffview.nvim" },
  config = function() require("crit").setup({}) end,
}
```

### lazy.nvim

```lua
{
  "ammar-ahmed22/crit.nvim",
  dependencies = { "sindrets/diffview.nvim" },
  opts = {},
}
```

### vim-plug

```vim
Plug 'sindrets/diffview.nvim'
Plug 'ammar-ahmed22/crit.nvim'
" ...then in init.lua:
lua require('crit').setup({})
```

## Commands

All commands start with `:Crit` so they are easy to remap. None of them have
default keybindings — wire up whatever you like in your own config.

| Command | Behaviour |
|---|---|
| `:CritAttach <id>` | Load a session by id. cd's into its repo, opens Diffview against its scope, paints existing draft comments as signs + virtual text. Warns if HEAD has drifted since the snapshot was taken. |
| `:CritDetach` | Clear the in-memory state and signs. Does not close Diffview. |
| `:CritComment` | Add a comment on the current line, or — with a range, e.g. `:'<,'>CritComment` — on the selected lines. The current buffer must be a Diffview file pane. |
| `:CritEdit` | Edit the comment under the cursor. If multiple comments overlap the line, pick one via `vim.ui.select`. |
| `:CritDelete` | Delete the comment under the cursor (with confirm). |
| `:CritList` | Populate the quickfix list with every draft comment. `<CR>` jumps to a comment in the right Diffview pane. |
| `:CritSubmit` | Open the submit window. Pick a verdict (`a`/`r`/`m`), type a summary, `<C-s>` to submit. Detaches on success. |
| `:CritShow` | Echo session metadata (id, status, scope, instructions). |
| `:CritOpen` | Open the upstream Bubble Tea TUI for the attached session in a terminal split. |
| `:CritDoctor` | Print dependency status. |
| `:CritLog` | Open the crit.nvim call log buffer. |

### Comment editor

| Key | Action |
|---|---|
| `<C-s>` | save and close |
| `<C-t>` | cycle kind: `comment` → `question` → `nit` → `blocking` |
| `q` / `<Esc>` | cancel |

### Submit window

| Key | Action |
|---|---|
| `a` / `r` / `m` | verdict: approve / request_changes / comment |
| `<C-s>` | submit |
| `q` / `<Esc>` | cancel |

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
  warn_on_head_drift = true,
})
```

## Typical agent flow

1. Coding agent makes changes.
2. Agent runs `crit session start --base main --title "..."` and tells you the
   id.
3. In nvim: `:CritAttach crit-7f3a2c`. Diffview opens.
4. Walk the diff. `V`+`:CritComment` to comment on a range. `:CritEdit` /
   `:CritDelete` as needed.
5. `:CritSubmit`. Pick verdict, type summary, `<C-s>`.
6. Agent's `crit session wait` returns the `review.json` and proceeds.

## Status

Early. The plugin is built on the `crit` headless CLI surface
(`crit session draft show`, `crit session comment add|edit|delete`,
`crit session submit`) — those are documented in
[`crit/AGENT.md`](https://github.com/ammar-ahmed22/crit/blob/main/AGENT.md#headless-human-surface-editor-integrations)
and stable. Bugs and feature requests welcome.

## License

MIT.
