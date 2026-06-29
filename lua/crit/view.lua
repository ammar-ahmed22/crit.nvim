-- view.lua renders a crit session's diff as an INLINE, single-window unified
-- diff using echasnovski/mini.diff's overlay mode, plus a file-picker sidebar.
-- It replaces the previous sindrets/diffview.nvim integration.
--
-- Why mini.diff: its overlay draws the diff (green adds / red deleted virtual
-- lines / changed lines) directly on top of the REAL file buffer. That keeps
-- full treesitter/LSP syntax highlighting and normal folding, and shows the
-- whole file rather than a synthetic diff scratch buffer.
--
-- The buffer shown is the NEW side of the diff (working tree / index / HEAD
-- depending on scope), so a buffer line number IS the new-side line number a
-- crit comment anchors to. mini.diff's `get_buf_data().hunks` carry the
-- reference (old) side line numbers for the (deferred) old-side workflow.
--
-- Layout (one dedicated tab):
--   ┌────────────┬─────────────────────────────────────┐
--   │ file picker│ inline diff (real buffer + overlay)  │
--   └────────────┴─────────────────────────────────────┘

local config = require("crit.config")
local util = require("crit.util")

local M = {}

-- One active view at a time, mirroring session.lua.
--   meta        the crit session metadata (repo, scope, base_ref, head_commit)
--   files       { { path, status } } changed files
--   tab/picker_win/picker_buf/diff_win
--   file_bufs   { [path] = bufnr }  diff buffers, created lazily, reused
--   buf_path    { [bufnr] = path }
--   old_rev     git rev used as the reference (old) side
local state = nil

-- has_mini reports whether mini.diff is importable.
function M.has_mini()
  return pcall(require, "mini.diff")
end

-- ensure_mini_ready makes sure mini.diff is actually able to DRAW.
--
-- The visualization (signs + overlay) is performed by a global decoration
-- provider that mini.diff registers ONLY inside MiniDiff.setup() (via
-- H.apply_config). It also creates its highlight groups and the auto-enable
-- autocmds there. If the user never called setup(), enable()/set_ref_text()
-- compute hunks but nothing is ever drawn — no green/red. So crit ensures
-- setup() has run exactly once.
--
-- We detect a prior setup() by the presence of the global `MiniDiff` table
-- (setup() does `_G.MiniDiff = MiniDiff`). If the user already set it up we do
-- NOT call setup() again (that would reset their config/mappings); we only
-- top up the highlight groups defensively. If they did not, we call setup()
-- once and then clear mini.diff's own `MiniDiff` autocommand group, which
-- removes its global `BufEnter` auto-enable so it does not start drawing git
-- signs in all of the user's normal buffers. The decoration provider that
-- setup() registers is global (not an autocmd), so clearing the group leaves
-- drawing intact; crit enables only its own diff buffers explicitly.
-- define_mini_hl sets crit's preferred links for mini.diff's overlay/sign
-- groups. When `force` is true the links are applied unconditionally; mini.diff
-- defines these same groups in its own setup() (with `default = true`), so crit
-- MUST force to win — otherwise `nvim_set_hl(..., { default = true })` is a
-- no-op against the already-defined group and crit's choices are ignored.
-- `force` is false only when the user set mini.diff up themselves, so their own
-- overlay colors are preserved.
local function define_mini_hl(force)
  local core = vim.fn.has("nvim-0.10") == 1
  local function hi(name, val)
    val.default = not force
    vim.api.nvim_set_hl(0, name, val)
  end
  hi("MiniDiffSignAdd",       { link = core and "Added" or "diffAdded" })
  hi("MiniDiffSignChange",    { link = core and "Changed" or "diffChanged" })
  hi("MiniDiffSignDelete",    { link = core and "Removed" or "diffRemoved" })
  hi("MiniDiffOverAdd",       { link = "DiffAdd" })
  -- MiniDiffOverChange highlights the OLD (reference) text of a changed line,
  -- shown as virtual text above the new line. Treat it as removed -> red,
  -- rather than mini.diff's default DiffText (often blue). MiniDiffOverChangeBuf
  -- is the NEW changed text and keeps its own (non-red) link so it does not
  -- inherit the deletion color.
  hi("MiniDiffOverChange",    { link = "DiffDelete" })
  hi("MiniDiffOverChangeBuf", { link = "DiffText" })
  hi("MiniDiffOverContext",   { link = "DiffChange" })
  hi("MiniDiffOverContextBuf", {})
  hi("MiniDiffOverDelete",    { link = "DiffDelete" })
end

local mini_ready = false
local mini_force_hl = false
local function ensure_mini_ready()
  if mini_ready then
    define_mini_hl(mini_force_hl)
    return
  end
  local mini = require("mini.diff")
  if _G.MiniDiff == nil then
    -- mini.diff has not been set up. setup() registers the (global) decoration
    -- provider that actually draws signs + overlay; without it nothing renders.
    pcall(mini.setup, {})
    -- Remove mini.diff's global auto-enable autocmds so it does not decorate
    -- the user's other buffers; crit enables its own diff buffers explicitly.
    pcall(vim.api.nvim_create_augroup, "MiniDiff", { clear = true })
    -- crit owns the overlay look here, so force its links (mini.diff already
    -- defined the groups in setup(), making `default` links a no-op).
    mini_force_hl = true
  end
  define_mini_hl(mini_force_hl)
  -- Keep crit's highlight links alive across colorscheme changes.
  pcall(vim.api.nvim_create_augroup, "CritViewMiniHl", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = "CritViewMiniHl",
    callback = function() define_mini_hl(mini_force_hl) end,
    desc = "Re-apply crit/mini.diff overlay highlights",
  })
  mini_ready = true
end

function M.is_open()
  return state ~= nil
    and state.tab ~= nil
    and vim.api.nvim_tabpage_is_valid(state.tab)
end

-- The custom mini.diff source: a no-op attach so set_ref_text works on buffers
-- that aren't tracked by mini.diff's default git source (e.g. an index/HEAD
-- snapshot loaded into a scratch buffer). crit drives the reference text.
local crit_source = {
  name = "crit",
  attach = function(_) return true end,
}

-- old_rev_for derives the git rev whose blobs form the OLD side, matching the
-- scope semantics crit's CLI uses:
--   worktree -> HEAD          (git diff HEAD)
--   staged   -> HEAD          (git diff --cached: index vs HEAD)
--   ref      -> merge-base(base_ref, HEAD)   (git diff base...HEAD)
local function old_rev_for(meta)
  if meta.scope == "ref" then
    if not meta.base_ref or meta.base_ref == "" then return nil end
    return util.git_merge_base(meta.repo, meta.base_ref)
  end
  return "HEAD"
end

-- name_status_range returns the `git diff` argument list for the scope.
local function name_status_range(meta)
  if meta.scope == "staged" then
    return { "--cached" }
  elseif meta.scope == "ref" then
    local base = old_rev_for(meta)
    return { (base or meta.base_ref) .. "...HEAD" }
  end
  return { "HEAD" }
end

-- new_side_lines returns the NEW-side content of `path` for the scope:
--   worktree -> the working-tree file (read from disk via the buffer)
--   staged   -> index content (git show :path)
--   ref      -> HEAD content (git show HEAD:path)
-- Returns (lines, is_ondisk). When is_ondisk is true the caller should :edit
-- the real file so highlighting/LSP attach naturally.
local function new_side_lines(meta, path)
  if meta.scope == "worktree" then
    return nil, true
  elseif meta.scope == "staged" then
    return util.git_show(meta.repo, ":", path) or {}, false
  else -- ref
    return util.git_show(meta.repo, "HEAD", path) or {}, false
  end
end

-- ensure_overlay turns mini.diff's overlay on for `buf` if it isn't already.
-- mini.diff resets overlay=false on every BufWinEnter, so this is re-asserted
-- by an autocmd as well as on first show.
local function ensure_overlay(buf)
  local mini = require("mini.diff")
  local d = mini.get_buf_data(buf)
  if d and not d.overlay then
    pcall(mini.toggle_overlay, buf)
  end
end

-- fold_unchanged collapses runs of unchanged lines far from any hunk, leaving
-- `ctx` lines of context around each change — the folded-context feel diffview
-- had. Operates on the diff window for `buf`.
local function fold_unchanged(win, buf, hunks)
  local n = vim.api.nvim_buf_line_count(buf)
  if n == 0 then return end
  -- Mark every line within ctx of a hunk's buffer range as "keep".
  local ctx = config.opts.view.context
  local keep = {}
  for _, h in ipairs(hunks) do
    local from = math.max(h.buf_start, 1)
    local to = h.buf_count > 0 and (h.buf_start + h.buf_count - 1) or from
    for l = math.max(from - ctx, 1), math.min(to + ctx, n) do
      keep[l] = true
    end
  end
  vim.api.nvim_win_call(win, function()
    vim.wo.foldmethod = "manual"
    vim.wo.foldenable = true
    vim.cmd("normal! zE") -- eliminate existing folds
    local l = 1
    while l <= n do
      if keep[l] then
        l = l + 1
      else
        local j = l
        while j <= n and not keep[j] do j = j + 1 end
        -- fold [l, j-1]
        if j - 1 > l then
          vim.cmd(string.format("%d,%dfold", l, j - 1))
        end
        l = j
      end
    end
  end)
end

-- render_file builds (or reuses) the diff buffer for `path` and returns bufnr.
local function render_file(path)
  local buf = state.file_bufs[path]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  local mini = require("mini.diff")
  local abs = state.meta.repo .. "/" .. path
  local lines, ondisk = new_side_lines(state.meta, path)

  if ondisk then
    -- Load the real file so treesitter/LSP attach to the actual on-disk path.
    buf = vim.fn.bufadd(abs)
    vim.fn.bufload(buf)
  else
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    -- Name it after the real path so filetype detection + the picker line up.
    pcall(vim.api.nvim_buf_set_name, buf, abs)
    vim.bo[buf].buftype = "" -- mini.diff only attaches to normal buffers
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
  end

  -- bufadd/bufload and nvim_buf_set_lines do not trigger filetype detection
  -- (that normally runs on :edit). Set it explicitly so treesitter/syntax
  -- highlighting attaches to the diff buffer.
  if vim.bo[buf].filetype == "" then
    local ft = vim.filetype.match({ filename = abs, buf = buf })
    if ft then vim.bo[buf].filetype = ft end
  end

  -- Per-buffer mini.diff config: our no-op source, so we (not its git source)
  -- own the reference text. This does NOT disturb the user's global setup.
  vim.b[buf].minidiff_config = { source = crit_source }

  -- Reference (old) side: the blob at old_rev. Missing blob (added file) -> "".
  local old = util.git_show(state.meta.repo, state.old_rev, path)
  local ref_text = old and (table.concat(old, "\n")) or ""

  mini.enable(buf)
  mini.set_ref_text(buf, ref_text)

  -- Re-assert overlay whenever this buffer is entered (mini.diff clears it on
  -- BufWinEnter), and repaint crit signs.
  local aug = vim.api.nvim_create_augroup("CritView_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = aug,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          ensure_overlay(buf)
          require("crit.ui.signs").paint()
        end
      end)
    end,
  })

  state.file_bufs[path] = buf
  state.buf_path[buf] = path
  return buf
end

-- status_marker maps a git status letter to the picker gutter.
local function status_marker(status)
  return ({ A = "A", D = "D", R = "R", C = "C", M = "M" })[status] or "M"
end

-- build_tree turns the flat { {path, status} } file list into a nested tree of
-- directory nodes and file leaves, then collapses single-child directory chains
-- (so e.g. `a/b/c/x.go` renders as one `a/b/c/` node rather than three nested
-- levels) — the same readability trick diffview's file panel uses.
--
-- Node shape:
--   dir  = { name, dir = true, children = { <node>... } }
--   file = { name, file = <the {path,status} entry> }
local function build_tree(files)
  local root = { name = "", dir = true, children = {}, _index = {} }
  for _, f in ipairs(files) do
    local node = root
    local parts = vim.split(f.path, "/", { plain = true })
    for i, part in ipairs(parts) do
      if i == #parts then
        node.children[#node.children + 1] = { name = part, file = f }
      else
        local child = node._index[part]
        if not child then
          child = { name = part, dir = true, children = {}, _index = {} }
          node._index[part] = child
          node.children[#node.children + 1] = child
        end
        node = child
      end
    end
  end

  -- Collapse chains: a dir with exactly one child that is itself a dir merges
  -- its name with the child's (path-joined).
  local function collapse(node)
    if node.dir then
      while #node.children == 1 and node.children[1].dir do
        local only = node.children[1]
        node.name = (node.name == "" and only.name) or (node.name .. "/" .. only.name)
        node.children = only.children
      end
      for _, c in ipairs(node.children) do collapse(c) end
      -- Sort: directories first, then files, each alphabetical.
      table.sort(node.children, function(a, b)
        local ad, bd = a.dir and 1 or 0, b.dir and 1 or 0
        if ad ~= bd then return ad > bd end
        return a.name < b.name
      end)
    end
  end
  collapse(root)
  return root
end

-- refresh_picker redraws the file tree with a live draft-comment count, and
-- rebuilds state.picker_rows so <CR> maps a rendered row back to its file.
function M.refresh_picker()
  if not M.is_open() then return end
  local session = require("crit.session")
  local tree = build_tree(state.files)
  local lines = {}
  local rows = {} -- rows[lnum] = file entry ({path,status}) or nil for dir lines

  local function render(node, depth)
    for _, child in ipairs(node.children) do
      local indent = string.rep("  ", depth)
      if child.dir then
        lines[#lines + 1] = string.format("%s %s/", indent, child.name)
        rows[#lines] = nil
        render(child, depth + 1)
      else
        local f = child.file
        local n = #session.comments_for(f.path, nil)
        local count = n > 0 and string.format("  (%d)", n) or ""
        lines[#lines + 1] = string.format("%s%s %s%s", indent, status_marker(f.status), child.name, count)
        rows[#lines] = f
      end
    end
  end
  render(tree, 0)

  state.picker_rows = rows
  if #lines == 0 then lines = { "(no changed files)" } end
  vim.bo[state.picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.picker_buf, 0, -1, false, lines)
  vim.bo[state.picker_buf].modifiable = false
end

-- show_file makes `path`'s diff buffer current in the diff window, enabling the
-- overlay and folding unchanged regions once mini.diff has computed hunks.
local function show_file(path)
  if not path then return end
  local buf = render_file(path)
  if not (state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)) then
    vim.api.nvim_set_current_win(state.picker_win)
    vim.cmd("rightbelow vsplit")
    state.diff_win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_win_set_buf(state.diff_win, buf)
  vim.api.nvim_set_current_win(state.diff_win)

  -- Hunks compute asynchronously after set_ref_text. mini.diff seeds `hunks`
  -- to an empty table immediately, so wait for a non-empty result (or the
  -- timeout, for a file with genuinely no hunks), redrawing so the scheduled
  -- diff update runs.
  local mini = require("mini.diff")
  vim.wait(500, function()
    vim.cmd("redraw")
    local d = mini.get_buf_data(buf)
    return d ~= nil and d.hunks ~= nil and #d.hunks > 0
  end, 20)
  ensure_overlay(buf)
  local d = mini.get_buf_data(buf)
  if d and d.hunks and #d.hunks > 0 and config.opts.view.fold_unchanged then
    fold_unchanged(state.diff_win, buf, d.hunks)
  end
  require("crit.ui.signs").paint()
end

-- open builds the tab/picker/diff window for session `meta` and shows the first
-- changed file. Returns true on success.
function M.open(meta)
  if not M.has_mini() then
    util.error("echasnovski/mini.diff is required for the inline diff view")
    return false
  end
  ensure_mini_ready()
  if M.is_open() then M.close() end

  state = {
    meta = meta,
    old_rev = old_rev_for(meta),
    files = {},
    file_bufs = {},
    buf_path = {},
  }
  if meta.scope == "ref" and not state.old_rev then
    util.error("session scope=ref but base_ref is empty")
    state = nil
    return false
  end

  local files, ferr = util.git_name_status(meta.repo, name_status_range(meta))
  if not files then
    util.error("git diff --name-status failed: " .. tostring(ferr))
    state = nil
    return false
  end
  state.files = files

  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()
  state.picker_win = vim.api.nvim_get_current_win()
  state.picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.picker_buf].buftype = "nofile"
  vim.bo[state.picker_buf].bufhidden = "wipe"
  vim.bo[state.picker_buf].swapfile = false
  vim.bo[state.picker_buf].filetype = "crit-picker"
  pcall(vim.api.nvim_buf_set_name, state.picker_buf, "crit://files")
  vim.api.nvim_win_set_buf(state.picker_win, state.picker_buf)
  vim.wo[state.picker_win].number = false
  vim.wo[state.picker_win].relativenumber = false
  vim.wo[state.picker_win].wrap = false
  vim.wo[state.picker_win].cursorline = true
  vim.wo[state.picker_win].winfixwidth = true

  vim.cmd("rightbelow vsplit")
  state.diff_win = vim.api.nvim_get_current_win()
  -- Width after the split, else the vsplit halves the picker.
  vim.api.nvim_win_set_width(state.picker_win, config.opts.view.picker_width)

  -- <CR> in the picker opens the file under the cursor (directory rows no-op).
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(state.picker_win)[1]
    local f = state.picker_rows and state.picker_rows[row]
    if f then show_file(f.path) end
  end, { buffer = state.picker_buf, nowait = true, silent = true })

  M.refresh_picker()
  if state.files[1] then
    show_file(state.files[1].path)
  else
    util.warn("no changed files in this session's diff")
  end
  return true
end

-- close tears down the view and its diff buffers.
function M.close()
  if not state then return end
  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    pcall(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)
  end
  local mini_ok, mini = pcall(require, "mini.diff")
  for _, buf in pairs(state.file_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      if mini_ok then pcall(mini.disable, buf) end
      -- Scratch (index/ref) buffers are ours to delete; on-disk worktree
      -- buffers are left alone so we don't disturb the user's editing.
      if vim.bo[buf].bufhidden ~= "" or vim.fn.bufname(buf) == "" then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
  state = nil
end

-- ---- Anchor mapping (used by init.lua / signs.lua / list.lua) -------------

-- buf_path returns the repo-relative path for a crit diff buffer, or nil.
function M.buf_path(bufnr)
  if not state then return nil end
  return state.buf_path[bufnr]
end

-- list_bufs returns every live crit diff buffer (for signs to walk).
function M.list_bufs()
  local out = {}
  if not state then return out end
  for _, buf in pairs(state.file_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then out[#out + 1] = buf end
  end
  return out
end

-- buffer_anchor returns (path, side) for `bufnr` (default current). The buffer
-- shows the new side, so side is always "new" here; old-side commenting is a
-- separate, deferred workflow.
function M.buffer_anchor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = M.buf_path(bufnr)
  if not path then return nil end
  return path, "new"
end

-- anchor_for_range resolves a display-line range in `bufnr` to a comment
-- anchor: path, side ("new"), start_line, end_line. Buffer lines map directly
-- to new-side line numbers. Returns nil if bufnr is not a crit diff buffer.
function M.anchor_for_range(bufnr, line1, line2)
  local path = M.buf_path(bufnr)
  if not path then return nil end
  if line2 < line1 then line1, line2 = line2, line1 end
  return path, "new", line1, line2
end

-- render_range maps a stored (side, start..end) anchor to display rows in
-- `bufnr`. New-side anchors are identity. Old-side anchors are mapped through
-- mini.diff hunks to the nearest buffer position (best-effort). Returns nil if
-- unmappable.
function M.render_range(bufnr, side, start_line, end_line)
  local path = M.buf_path(bufnr)
  if not path then return nil end
  if side == "new" then
    return start_line, end_line
  end
  -- Old side: find the hunk whose ref range contains start_line and translate
  -- to its buffer anchor (deleted lines render as virtual lines above
  -- buf_start, so we anchor the sign to buf_start).
  local mini = require("mini.diff")
  local d = mini.get_buf_data(bufnr)
  if not d or not d.hunks then return nil end
  for _, h in ipairs(d.hunks) do
    local rfrom, rto = h.ref_start, h.ref_start + math.max(h.ref_count, 1) - 1
    if start_line >= rfrom and start_line <= rto then
      local row = math.max(h.buf_start, 1)
      return row, row
    end
  end
  return nil
end

-- focus_anchor selects `path` in the picker, shows its diff, and moves the
-- cursor to the row for (side, line). Returns true on success.
function M.focus_anchor(path, side, line)
  if not M.is_open() then
    util.warn("no active crit diff view")
    return false
  end
  local known = false
  for _, f in ipairs(state.files) do
    if f.path == path then known = true break end
  end
  if not known then return false end
  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    pcall(vim.api.nvim_set_current_tabpage, state.tab)
  end
  show_file(path)
  local buf = state.file_bufs[path]
  local row = line
  if side ~= "new" then
    local r = M.render_range(buf, side, line, line)
    row = r or line
  end
  pcall(vim.api.nvim_win_set_cursor, state.diff_win, { math.max(row, 1), 0 })
  -- Keep the picker highlight in sync.
  -- Move the picker cursor to the tree row showing this file.
  if state.picker_rows then
    for row, f in pairs(state.picker_rows) do
      if f and f.path == path then
        pcall(vim.api.nvim_win_set_cursor, state.picker_win, { row, 0 })
        break
      end
    end
  end
  return true
end

return M
