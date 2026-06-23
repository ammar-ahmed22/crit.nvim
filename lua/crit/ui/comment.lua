-- comment.lua renders the floating-window comment editor. It is used for both
-- ":CritComment" (new comment) and ":CritEdit" (existing comment).

local M = {}

local KINDS = { "comment", "question", "nit", "blocking" }

local function cycle_kind(current)
  for i, k in ipairs(KINDS) do
    if k == current then
      return KINDS[(i % #KINDS) + 1]
    end
  end
  return KINDS[1]
end

local function center_rect()
  local cols = vim.o.columns
  local rows = vim.o.lines
  local w = math.min(80, math.floor(cols * 0.7))
  local h = math.min(16, math.floor(rows * 0.5))
  return {
    relative = "editor",
    width = w,
    height = h,
    col = math.floor((cols - w) / 2),
    row = math.floor((rows - h) / 2),
    style = "minimal",
    border = "rounded",
  }
end

-- open creates the floating editor.
-- spec: {
--   title         = string  (window title)
--   anchor_label  = string  (e.g. "foo.go [new] L41-44")
--   snippet       = string  (snippet shown read-only above body)
--   initial_body  = string?
--   initial_kind  = string? (default "comment")
--   on_submit     = function(body, kind)
--   on_cancel     = function()?
-- }
function M.open(spec)
  local kind = spec.initial_kind or "comment"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"

  local lines = {}
  table.insert(lines, "# " .. (spec.title or "Comment"))
  table.insert(lines, "anchor: " .. (spec.anchor_label or ""))
  table.insert(lines, "kind:   " .. kind)
  table.insert(lines, "")
  table.insert(lines, "-- snippet (read-only) ---------------------------------")
  for line in string.gmatch((spec.snippet or "") .. "\n", "([^\n]*)\n") do
    table.insert(lines, line)
  end
  table.insert(lines, "-- body (type below) -----------------------------------")
  local body_start = #lines + 1
  for line in string.gmatch((spec.initial_body or "") .. "\n", "([^\n]*)\n") do
    table.insert(lines, line)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local rect = center_rect()
  local win = vim.api.nvim_open_win(buf, true, rect)
  vim.wo[win].wrap = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false

  vim.api.nvim_win_set_cursor(win, { #lines, 0 })

  local function read_body()
    local total = vim.api.nvim_buf_line_count(buf)
    local body_lines = vim.api.nvim_buf_get_lines(buf, body_start - 1, total, false)
    while #body_lines > 0 and body_lines[#body_lines] == "" do
      table.remove(body_lines)
    end
    return table.concat(body_lines, "\n")
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local body = read_body()
    close()
    spec.on_submit(body, kind)
  end

  local function cancel()
    close()
    if spec.on_cancel then spec.on_cancel() end
  end

  local function refresh_kind_line()
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "kind:   " .. kind })
  end

  local function toggle_kind()
    kind = cycle_kind(kind)
    refresh_kind_line()
  end

  local map = function(modes, lhs, fn)
    if type(modes) == "string" then modes = { modes } end
    for _, mode in ipairs(modes) do
      vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
  end

  map({ "n", "i" }, "<C-s>", submit)
  map({ "n", "i" }, "<C-t>", toggle_kind)
  map("n", "q", cancel)
  map("n", "<Esc>", cancel)

  -- Drop into insert mode at the end of the buffer so the user can just start
  -- typing the body.
  vim.cmd("startinsert!")
end

return M
