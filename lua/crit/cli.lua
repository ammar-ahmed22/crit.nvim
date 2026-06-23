local config = require("crit.config")
local util = require("crit.util")

local M = {}

-- build_args concatenates global flags (--sessions-dir) with the call args.
local function build_args(args)
  local out = { config.opts.bin }
  if config.opts.sessions_dir and config.opts.sessions_dir ~= "" then
    table.insert(out, "--sessions-dir")
    table.insert(out, config.opts.sessions_dir)
  end
  for _, a in ipairs(args) do
    table.insert(out, a)
  end
  return out
end

-- run executes the crit binary with `args` and returns:
--   { code, stdout (string), stderr (string), json (parsed table or nil) }
-- opts:
--   stdin = string?    fed to the process on stdin
--   json  = boolean    when true, attempt vim.json.decode on stdout
--   cwd   = string?    run dir
function M.run(args, opts)
  opts = opts or {}
  local cmd = build_args(args)
  util.info("exec: " .. table.concat(cmd, " "))

  local sys_opts = { text = true }
  if opts.cwd then sys_opts.cwd = opts.cwd end
  if opts.stdin then sys_opts.stdin = opts.stdin end

  local res = vim.system(cmd, sys_opts):wait()
  local stdout = res.stdout or ""
  local stderr = res.stderr or ""

  if stderr ~= "" then
    util.info("stderr: " .. stderr)
  end

  local json = nil
  if opts.json and stdout ~= "" then
    local ok, decoded = pcall(vim.json.decode, stdout, { luanil = { object = true, array = true } })
    if ok then json = decoded end
  end

  return {
    code = res.code,
    stdout = stdout,
    stderr = stderr,
    json = json,
    cmd = cmd,
  }
end

-- ---- Convenience wrappers for each subcommand ----------------------------

function M.session_show(id)
  return M.run({ "session", "show", id, "--json" }, { json = true })
end

function M.session_draft_show(id)
  return M.run({ "session", "draft", "show", id }, { json = true })
end

function M.session_comment_add(id, params)
  local args = { "session", "comment", "add", id,
    "--file", params.file,
    "--side", params.side,
    "--start", tostring(params.start_line),
    "--end", tostring(params.end_line),
    "--kind", params.kind or "comment",
    "--body", "-",
  }
  return M.run(args, { stdin = params.body or "", json = true })
end

function M.session_comment_edit(id, cid, params)
  local args = { "session", "comment", "edit", id, cid }
  local stdin = nil
  if params.body ~= nil then
    table.insert(args, "--body"); table.insert(args, "-")
    stdin = params.body
  end
  if params.kind then
    table.insert(args, "--kind"); table.insert(args, params.kind)
  end
  if params.file then
    table.insert(args, "--file"); table.insert(args, params.file)
  end
  if params.side then
    table.insert(args, "--side"); table.insert(args, params.side)
  end
  if params.start_line then
    table.insert(args, "--start"); table.insert(args, tostring(params.start_line))
  end
  if params.end_line then
    table.insert(args, "--end"); table.insert(args, tostring(params.end_line))
  end
  return M.run(args, { stdin = stdin, json = true })
end

function M.session_comment_delete(id, cid)
  return M.run({ "--json", "session", "comment", "delete", id, cid }, { json = true })
end

function M.session_submit(id, verdict, summary)
  local args = { "session", "submit", id, "--verdict", verdict }
  local stdin = nil
  if summary and summary ~= "" then
    table.insert(args, "--summary"); table.insert(args, "-")
    stdin = summary
  end
  return M.run(args, { stdin = stdin, json = true })
end

function M.session_cancel(id)
  return M.run({ "--json", "session", "cancel", id }, { json = true })
end

return M
