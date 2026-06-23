-- signs.lua paints draft comments onto Diffview buffers as gutter signs and
-- end-of-line virtual text.

local config = require("crit.config")
local session = require("crit.session")
local diffview = require("crit.diffview")

local M = {}

local SIGN_PREFIX = "CritKind_"
local NS = vim.api.nvim_create_namespace("crit.signs")

local signs_defined = false

local function define_signs()
  if signs_defined then return end
  for kind, spec in pairs(config.opts.signs) do
    vim.fn.sign_define(SIGN_PREFIX .. kind, {
      text = spec.text,
      texthl = spec.hl,
    })
  end
  signs_defined = true
end

-- clear removes every crit sign + extmark from every loaded buffer.
function M.clear()
  vim.fn.sign_unplace(config.opts.sign_group)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      vim.api.nvim_buf_clear_namespace(b, NS, 0, -1)
    end
  end
end

-- paint walks every loaded buffer, asks Diffview which (file, side) it
-- represents, and places signs + virt_text for every matching comment.
function M.paint()
  define_signs()
  M.clear()
  if not session.is_attached() then return end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local file, side = diffview.buffer_anchor(buf)
      if file and side then
        local comments = session.comments_for(file, side)
        for _, c in ipairs(comments) do
          M.paint_one(buf, c)
        end
      end
    end
  end
end

-- paint_one places sign + virt_text for a single comment in buf.
function M.paint_one(buf, c)
  local kind_spec = config.opts.signs[c.kind] or config.opts.signs.comment
  local sign_name = SIGN_PREFIX .. (config.opts.signs[c.kind] and c.kind or "comment")
  for lnum = c.start_line, c.end_line do
    vim.fn.sign_place(0, config.opts.sign_group, sign_name, buf, {
      lnum = lnum,
      priority = 10,
    })
  end
  if config.opts.virt_text.enabled then
    local body = (c.body or ""):gsub("\n", " ")
    local first_line = body
    if #first_line > config.opts.virt_text.max_chars then
      first_line = first_line:sub(1, config.opts.virt_text.max_chars - 1) .. "…"
    end
    local virt = config.opts.virt_text.prefix .. first_line
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, c.end_line - 1, 0, {
      virt_text = { { virt, config.opts.virt_text.hl } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end
  -- Ignore kind_spec lookup result; we only used it to validate the kind.
  local _ = kind_spec
end

return M
