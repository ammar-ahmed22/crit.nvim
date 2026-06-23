-- crit.nvim user commands. Defining these here (rather than only inside
-- require('crit').setup()) means they are available without a config call, so
-- users on packer who forget to call setup() still get a working :CritDoctor.

if vim.g.loaded_crit == 1 then return end
vim.g.loaded_crit = 1

local function crit() return require("crit") end

vim.api.nvim_create_user_command("CritAttach", function(args)
  crit().attach(args.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command("CritDetach", function() crit().detach() end, {})

vim.api.nvim_create_user_command("CritComment", function(args)
  crit().comment_new(args.line1, args.line2)
end, { range = true })

vim.api.nvim_create_user_command("CritEdit", function() crit().comment_edit() end, {})

vim.api.nvim_create_user_command("CritDelete", function() crit().comment_delete() end, {})

vim.api.nvim_create_user_command("CritList", function() crit().list() end, {})

vim.api.nvim_create_user_command("CritSubmit", function() crit().submit() end, {})

vim.api.nvim_create_user_command("CritShow", function() crit().show() end, {})

vim.api.nvim_create_user_command("CritOpen", function() crit().open_tui() end, {})

vim.api.nvim_create_user_command("CritDoctor", function() crit().doctor() end, {})

vim.api.nvim_create_user_command("CritLog", function() crit().open_log() end, {})
