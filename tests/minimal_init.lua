-- Minimal init for headless plenary runs.
-- Usage:
--   nvim --headless -u tests/minimal_init.lua \
--        -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.env.HOME .. "/.local/share/nvim/lazy/plenary.nvim")
vim.opt.runtimepath:prepend(vim.env.HOME .. "/.local/share/nvim/site/pack/packer/start/plenary.nvim")
