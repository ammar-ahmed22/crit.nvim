-- diffview.lua opens an existing crit session in sindrets/diffview.nvim and
-- maps Diffview buffers back to (file, side) anchors used by crit.

local util = require("crit.util")
local M = {}

-- open invokes :DiffviewOpen with arguments matching the session's scope.
--   worktree  -> :DiffviewOpen
--   staged    -> :DiffviewOpen --cached
--   ref <r>   -> :DiffviewOpen <r>...HEAD
function M.open(scope, base_ref)
  if scope == "worktree" then
    vim.cmd("DiffviewOpen")
  elseif scope == "staged" then
    vim.cmd("DiffviewOpen --cached")
  elseif scope == "ref" then
    if not base_ref or base_ref == "" then
      util.error("session scope=ref but base_ref is empty")
      return false
    end
    vim.cmd(string.format("DiffviewOpen %s...HEAD", base_ref))
  else
    util.error("unknown scope " .. tostring(scope))
    return false
  end
  return true
end

-- current_view returns the active diffview View, or nil.
function M.current_view()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then return nil end
  return lib.get_current_view()
end

-- buffer_anchor inspects buffer `bufnr` (defaulting to the current buffer) and
-- returns its (file, side) pair if it belongs to the active Diffview view, or
-- nil if the buffer isn't a diffview file pane.
--
-- Diffview opens each changed file as a pair of buffers. Each buffer carries
-- the file metadata on its FileEntry via the view; we walk the file panel to
-- find which entry/buffer the user is sitting on.
function M.buffer_anchor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local view = M.current_view()
  if not view or not view.files then return nil end
  for _, entry in ipairs(view.files) do
    local left = entry.layout and entry.layout.a and entry.layout.a.file and entry.layout.a.file.bufnr
    local right = entry.layout and entry.layout.b and entry.layout.b.file and entry.layout.b.file.bufnr
    -- Fall back to common older field names if the modern layout isn't there.
    if not left then left = entry.left and entry.left.bufnr end
    if not right then right = entry.right and entry.right.bufnr end

    local path = entry.path or (entry.basename and entry.basename) or nil
    if not path and entry.absolute_path then
      path = vim.fn.fnamemodify(entry.absolute_path, ":.")
    end
    if path then
      if bufnr == left then return path, "old" end
      if bufnr == right then return path, "new" end
    end
  end
  return nil
end

-- focus_anchor activates the diffview file panel entry for `file` and moves
-- the cursor to (line, 1) on the chosen side. Returns true on success.
function M.focus_anchor(file, side, line)
  local view = M.current_view()
  if not view or not view.files then
    util.warn("no active Diffview view")
    return false
  end
  for _, entry in ipairs(view.files) do
    local path = entry.path or (entry.absolute_path and vim.fn.fnamemodify(entry.absolute_path, ":."))
    if path == file then
      if view.set_file then
        pcall(view.set_file, view, entry, true)
      end
      local buf
      if side == "new" then
        buf = entry.layout and entry.layout.b and entry.layout.b.file and entry.layout.b.file.bufnr
        if not buf then buf = entry.right and entry.right.bufnr end
      else
        buf = entry.layout and entry.layout.a and entry.layout.a.file and entry.layout.a.file.bufnr
        if not buf then buf = entry.left and entry.left.bufnr end
      end
      if buf then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == buf then
            vim.api.nvim_set_current_win(win)
            vim.api.nvim_win_set_cursor(win, { math.max(line, 1), 0 })
            return true
          end
        end
      end
      return true
    end
  end
  return false
end

return M
