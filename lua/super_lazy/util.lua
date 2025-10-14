local M = {}

function M.notify(msg, level)
  vim.notify("super_lazy.nvim: " .. msg, level or vim.log.levels.INFO, { title = "super_lazy.nvim" })
end

return M
