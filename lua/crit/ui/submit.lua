-- submit.lua renders the floating-window submit form.

local M = {}

local VERDICTS = {
  a = { value = "approve",         label = "approve" },
  r = { value = "request_changes", label = "request_changes" },
  m = { value = "comment",         label = "comment" },
}

local function center_rect()
  local cols = vim.o.columns
  local rows = vim.o.lines
  local w = math.min(96, math.floor(cols * 0.8))
  local h = math.min(24, math.floor(rows * 0.7))
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

-- open shows the submit form.
-- spec: {
--   session_id  = string
--   comments    = list of comment objects
--   on_submit   = function(verdict, summary)
--   on_cancel   = function()?
-- }
function M.open(spec)
  local verdict = "comment"
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"

  local lines = {}
  table.insert(lines, "# Submit review for " .. spec.session_id)
  table.insert(lines, "verdict: " .. verdict .. "   (a=approve  r=request_changes  m=comment)")
  table.insert(lines, "")
  table.insert(lines, "-- comments --------------------------------------------")
  if #spec.comments == 0 then
    table.insert(lines, "(no comments)")
  else
    for _, c in ipairs(spec.comments) do
      table.insert(lines, string.format("[%s] %s [%s] L%d-%d",
        c.id or "", c.file or "", c.side or "", c.start_line or 0, c.end_line or 0))
      table.insert(lines, "  " .. (c.kind or "comment") .. ": " .. (c.body or ""):gsub("\n", " "))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "-- summary (type below) --------------------------------")
  local summary_start = #lines + 1
  table.insert(lines, "")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local rect = center_rect()
  local win = vim.api.nvim_open_win(buf, true, rect)
  vim.wo[win].wrap = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false

  vim.api.nvim_win_set_cursor(win, { #lines, 0 })

  local function read_summary()
    local total = vim.api.nvim_buf_line_count(buf)
    local sum_lines = vim.api.nvim_buf_get_lines(buf, summary_start - 1, total, false)
    while #sum_lines > 0 and sum_lines[#sum_lines] == "" do
      table.remove(sum_lines)
    end
    return table.concat(sum_lines, "\n")
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local summary = read_summary()
    close()
    spec.on_submit(verdict, summary)
  end

  local function cancel()
    close()
    if spec.on_cancel then spec.on_cancel() end
  end

  local function refresh_verdict_line()
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, {
      "verdict: " .. verdict .. "   (a=approve  r=request_changes  m=comment)",
    })
  end

  local map = function(modes, lhs, fn)
    if type(modes) == "string" then modes = { modes } end
    for _, mode in ipairs(modes) do
      vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
  end

  for key, v in pairs(VERDICTS) do
    map("n", key, function()
      verdict = v.value
      refresh_verdict_line()
    end)
  end
  map({ "n", "i" }, "<C-s>", submit)
  map("n", "q", cancel)
  map("n", "<Esc>", cancel)
end

return M
