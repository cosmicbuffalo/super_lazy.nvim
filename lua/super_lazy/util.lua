local M = {}

function M.notify(msg, level)
  vim.notify("super_lazy.nvim: " .. msg, level or vim.log.levels.INFO, { title = "super_lazy.nvim" })
end

function M.format_path(path)
  local resolved = vim.fn.resolve(path)
  local home = vim.fn.expand("~")
  if resolved:sub(1, #home) == home then
    return "~" .. resolved:sub(#home + 1)
  end
  return resolved
end

return M
