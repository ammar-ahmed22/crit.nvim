local M = {}

function M.log_buf_name()
  return "crit://log"
end

local function ensure_log_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == M.log_buf_name() then
      return b
    end
  end
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(b, M.log_buf_name())
  vim.bo[b].buftype = "nofile"
  vim.bo[b].filetype = "crit-log"
  return b
end

function M.log(level, msg)
  local stamp = os.date("%H:%M:%S")
  local prefix = string.format("[%s] %s ", stamp, level)
  local lines = {}
  for line in string.gmatch(tostring(msg), "[^\n]+") do
    table.insert(lines, prefix .. line)
  end
  if #lines == 0 then lines = { prefix } end
  local buf = ensure_log_buf()
  local last = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, last, last, false, lines)
end

function M.info(msg)  M.log("INFO",  msg) end
function M.warn(msg)
  M.log("WARN", msg)
  vim.notify("[crit] " .. msg, vim.log.levels.WARN)
end
function M.error(msg)
  M.log("ERROR", msg)
  vim.notify("[crit] " .. msg, vim.log.levels.ERROR)
end

-- has_executable returns true if `name` resolves on $PATH.
function M.has_executable(name)
  return vim.fn.executable(name) == 1
end

-- has_module returns true if `mod` can be `require()`d without raising.
function M.has_module(mod)
  local ok = pcall(require, mod)
  return ok
end

-- repo_root runs `git rev-parse --show-toplevel` and returns the trimmed path,
-- or nil + an error message.
function M.repo_root(cwd)
  local out = vim.fn.systemlist({ "git", "-C", cwd or ".", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(out, "\n")
  end
  return out[1]
end

-- git_head returns the current HEAD sha (full), or nil + an error.
function M.git_head(cwd)
  local out = vim.fn.systemlist({ "git", "-C", cwd or ".", "rev-parse", "HEAD" })
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(out, "\n")
  end
  return out[1]
end

-- visual_range returns the inclusive [start_lnum, end_lnum] of the most recent
-- visual selection (the `<` `>` marks). Returns nil when no selection exists.
function M.visual_range()
  local s = vim.fn.getpos("'<")[2]
  local e = vim.fn.getpos("'>")[2]
  if s == 0 or e == 0 then return nil end
  if e < s then s, e = e, s end
  return s, e
end

-- truncate clips s to n chars with an ellipsis if needed.
function M.truncate(s, n)
  if #s <= n then return s end
  if n <= 1 then return s:sub(1, n) end
  return s:sub(1, n - 1) .. "…"
end

-- short_sha shortens a sha to its leading 8 chars (empty input passes through).
function M.short_sha(sha)
  if not sha or sha == "" then return sha end
  return sha:sub(1, 8)
end

return M
