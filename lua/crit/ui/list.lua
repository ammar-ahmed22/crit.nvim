-- list.lua populates the quickfix list with every draft comment so the user
-- can :CritList -> <CR> to jump to any comment.

local session = require("crit.session")
local diffview = require("crit.diffview")
local util = require("crit.util")

local M = {}

function M.open()
  if not session.is_attached() then
    util.warn("no crit session attached")
    return
  end
  local items = {}
  for _, c in ipairs(session.state.comments) do
    local text = string.format("[%s/%s] %s: %s",
      c.id or "?", c.kind or "comment",
      c.side or "?", (c.body or ""):gsub("\n", " "))
    table.insert(items, {
      filename = c.file,
      lnum = c.start_line or 1,
      text = text,
    })
  end
  vim.fn.setqflist({}, "r", { title = "crit:" .. session.state.id, items = items })
  vim.cmd("copen")

  -- When the user hits <CR>, focus the comment in the right Diffview pane
  -- rather than letting :cnext drop them into an editing buffer.
  local qf_buf = vim.api.nvim_get_current_buf()
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local c = session.state.comments[row]
    if not c then return end
    vim.cmd("wincmd p")
    diffview.focus_anchor(c.file, c.side, c.start_line)
  end, { buffer = qf_buf, nowait = true, silent = true })
end

return M
