local M = {}

M.defaults = {
  bin = "crit",
  sessions_dir = nil,
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
    context = 3,            -- lines of context kept around each hunk when folding
  },
  warn_on_head_drift = true,
}

M.opts = vim.deepcopy(M.defaults)

function M.setup(user)
  M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user or {})
end

return M
