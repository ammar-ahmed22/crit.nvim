-- crit.nvim public API. plugin/crit.lua registers user commands that delegate
-- to these functions.

local config = require("crit.config")
local util = require("crit.util")
local cli = require("crit.cli")
local session = require("crit.session")
local view = require("crit.view")
local signs = require("crit.ui.signs")
local comment_ui = require("crit.ui.comment")
local submit_ui = require("crit.ui.submit")
local list_ui = require("crit.ui.list")

local M = {}

function M.setup(user)
  config.setup(user)
end

local function check_deps()
  if not util.has_executable(config.opts.bin) then
    util.error(("crit binary %q not on $PATH"):format(config.opts.bin))
    return false
  end
  if not util.has_module("mini.diff") then
    util.error("echasnovski/mini.diff is required")
    return false
  end
  return true
end

-- ---- Attach / detach -----------------------------------------------------

function M.attach(id)
  if not check_deps() then return end
  if not id or id == "" then
    util.error("usage: :CritAttach <id>")
    return
  end

  local show = cli.session_show(id)
  if show.code ~= 0 or not show.json then
    util.error(("crit session show %s failed (exit %d): %s"):format(id, show.code, show.stderr))
    return
  end
  local meta = show.json
  if meta.status == "submitted" or meta.status == "cancelled" or meta.status == "responded" then
    util.warn(("session %s is %s; opening in read-only mode"):format(id, meta.status))
  end

  if vim.fn.isdirectory(meta.repo) ~= 1 then
    util.error("session repo path does not exist: " .. tostring(meta.repo))
    return
  end
  vim.cmd("lcd " .. vim.fn.fnameescape(meta.repo))

  if config.opts.warn_on_head_drift and meta.head_commit and meta.head_commit ~= "" then
    local head = util.git_head(meta.repo)
    if head and head ~= meta.head_commit then
      util.warn(("HEAD moved since session start: session=%s, HEAD=%s"):format(
        util.short_sha(meta.head_commit), util.short_sha(head)))
    end
  end

  if not view.open(meta) then
    return
  end

  local d = cli.session_draft_show(id)
  if d.code ~= 0 then
    util.error("could not read draft: " .. d.stderr)
    return
  end
  session.attach(meta, d.json or { comments = {} })
  vim.defer_fn(function() signs.paint() end, 50)
  util.info(("attached %s (%d existing comment(s))"):format(id, #(session.state.comments or {})))
end

function M.detach()
  signs.clear()
  view.close()
  session.detach()
  util.info("detached")
end

-- ---- Comment workflows ---------------------------------------------------

-- resolve_anchor_at_cursor inspects the current window/buffer and returns the
-- comment-anchor coordinates for the cursor or the last visual selection.
--
-- The inline view shows the new side of the file, so a buffer line number is
-- the new-side line a comment anchors to; view.anchor_for_range maps the
-- selected rows to (file, side, start, end).
local function resolve_anchor_at_cursor(line1, line2)
  local buf = vim.api.nvim_get_current_buf()
  if not view.buf_path(buf) then
    util.warn("cursor is not in a crit diff buffer")
    return nil
  end
  local r1, r2
  if line1 and line2 and line1 ~= line2 then
    r1, r2 = line1, line2
  elseif line1 then
    r1, r2 = line1, line1
  else
    local s, e = util.visual_range()
    if s then
      r1, r2 = s, e
    else
      local row = vim.api.nvim_win_get_cursor(0)[1]
      r1, r2 = row, row
    end
  end
  return view.anchor_for_range(buf, r1, r2)
end

local function refresh_draft_and_paint()
  if not session.is_attached() then return end
  local d = cli.session_draft_show(session.state.id)
  if d.code == 0 and d.json then
    session.replace_comments(d.json.comments or {})
    signs.paint()
  end
end

function M.comment_new(line1, line2)
  if not session.is_attached() then
    util.error("no crit session attached (:CritAttach <id>)")
    return
  end
  local file, side, sline, eline = resolve_anchor_at_cursor(line1, line2)
  if not file then return end

  comment_ui.open({
    title = "New comment",
    anchor_label = string.format("%s [%s] L%d-%d", file, side, sline, eline),
    snippet = "",
    on_submit = function(body, kind)
      if body == "" then
        util.warn("empty body, nothing saved")
        return
      end
      local res = cli.session_comment_add(session.state.id, {
        file = file, side = side, start_line = sline, end_line = eline,
        body = body, kind = kind,
      })
      if res.code ~= 0 then
        util.error("comment add failed: " .. res.stderr)
        return
      end
      refresh_draft_and_paint()
    end,
  })
end

local function pick_comment_under_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if not view.buf_path(buf) then
    util.warn("cursor is not in a crit diff buffer")
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local file, side = view.anchor_for_range(buf, row, row)
  local hits = session.comments_at(file, side, row)
  if #hits == 0 then
    util.warn("no comment on this line")
    return nil
  end
  if #hits == 1 then return hits[1] end

  local idx = nil
  vim.ui.select(hits, {
    prompt = "Select comment:",
    format_item = function(c) return string.format("%s [%s] %s", c.id, c.kind, (c.body or ""):gsub("\n", " ")) end,
  }, function(_, i) idx = i end)
  if not idx then return nil end
  return hits[idx]
end

function M.comment_edit()
  if not session.is_attached() then
    util.error("no crit session attached")
    return
  end
  local c = pick_comment_under_cursor()
  if not c then return end

  comment_ui.open({
    title = "Edit comment " .. c.id,
    anchor_label = string.format("%s [%s] L%d-%d", c.file, c.side, c.start_line, c.end_line),
    snippet = c.code_snippet or "",
    initial_body = c.body or "",
    initial_kind = c.kind or "comment",
    on_submit = function(body, kind)
      local res = cli.session_comment_edit(session.state.id, c.id, {
        body = body, kind = kind,
      })
      if res.code ~= 0 then
        util.error("comment edit failed: " .. res.stderr)
        return
      end
      refresh_draft_and_paint()
    end,
  })
end

function M.comment_delete()
  if not session.is_attached() then
    util.error("no crit session attached")
    return
  end
  local c = pick_comment_under_cursor()
  if not c then return end
  local confirm = vim.fn.confirm(("Delete comment %s?"):format(c.id), "&Yes\n&No", 2)
  if confirm ~= 1 then return end
  local res = cli.session_comment_delete(session.state.id, c.id)
  if res.code ~= 0 then
    util.error("comment delete failed: " .. res.stderr)
    return
  end
  refresh_draft_and_paint()
end

function M.list()
  list_ui.open()
end

function M.submit()
  if not session.is_attached() then
    util.error("no crit session attached")
    return
  end
  submit_ui.open({
    session_id = session.state.id,
    comments = session.state.comments,
    on_submit = function(verdict, summary)
      local res = cli.session_submit(session.state.id, verdict, summary)
      if res.code ~= 0 then
        util.error("submit failed: " .. res.stderr)
        return
      end
      util.info("submitted " .. session.state.id)
      M.detach()
    end,
  })
end

function M.show()
  if not session.is_attached() then
    util.error("no crit session attached")
    return
  end
  local s = session.state
  vim.api.nvim_echo({
    { "[crit] ", "Title" },
    { s.id .. " ", "Identifier" },
    { "(" .. s.status .. ")", "Comment" },
    { "  scope=" .. s.scope, "Comment" },
  }, false, {})
  if s.instructions ~= "" then
    vim.api.nvim_echo({ { s.instructions, "Normal" } }, false, {})
  end
end

function M.open_tui()
  if not session.is_attached() then
    util.error("no crit session attached")
    return
  end
  vim.cmd("tabnew | terminal " .. config.opts.bin .. " open " .. session.state.id)
end

function M.doctor()
  local lines = { "[crit doctor]" }
  if util.has_executable(config.opts.bin) then
    local v = vim.fn.systemlist({ config.opts.bin, "--version" })
    table.insert(lines, "  crit binary: " .. table.concat(v, " "))
  else
    table.insert(lines, "  crit binary: NOT FOUND on $PATH (set config.bin or install via `go install`)")
  end
  if util.has_module("mini.diff") then
    table.insert(lines, "  mini.diff: ok")
  else
    table.insert(lines, "  mini.diff: NOT INSTALLED (required)")
  end
  for _, ln in ipairs(lines) do print(ln) end
end

function M.open_log()
  vim.cmd("split " .. util.log_buf_name())
end

return M
