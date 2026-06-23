-- session.lua holds the in-memory state for the currently-attached session.
-- There is at most one active session per nvim instance; reattaching to a
-- different id replaces the state.

local M = {}

M.state = nil

-- attach records a freshly-loaded session + draft.
function M.attach(meta, draft)
  M.state = {
    id = meta.id,
    repo = meta.repo,
    scope = meta.scope,
    base_ref = meta.base_ref,
    head_commit = meta.head_commit,
    status = meta.status,
    instructions = meta.instructions or "",
    comments = (draft and draft.comments) or {},
    verdict = (draft and draft.verdict) or "",
    summary = (draft and draft.summary) or "",
  }
end

function M.detach()
  M.state = nil
end

function M.is_attached()
  return M.state ~= nil
end

-- replace_comments swaps the comment list (e.g. after a refresh from
-- `session draft show`).
function M.replace_comments(comments)
  if not M.state then return end
  M.state.comments = comments or {}
end

-- comments_for returns the subset matching (file, side). Caller may pass
-- side=nil to match either side.
function M.comments_for(file, side)
  if not M.state then return {} end
  local out = {}
  for _, c in ipairs(M.state.comments) do
    if c.file == file and (side == nil or c.side == side) then
      table.insert(out, c)
    end
  end
  return out
end

-- find_comment_by_id returns the comment object with the given id, or nil.
function M.find_comment_by_id(cid)
  if not M.state then return nil end
  for _, c in ipairs(M.state.comments) do
    if c.id == cid then return c end
  end
  return nil
end

-- comments_at returns every comment whose anchor range includes lnum, on the
-- given (file, side).
function M.comments_at(file, side, lnum)
  local out = {}
  for _, c in ipairs(M.comments_for(file, side)) do
    if lnum >= c.start_line and lnum <= c.end_line then
      table.insert(out, c)
    end
  end
  return out
end

return M
