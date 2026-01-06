local M = {}

M.COMPATIBLE_LAZY_VERSION = "11.17.5"

local default_config = {
  lockfile_repo_dirs = { vim.fn.stdpath("config") },
}

M.options = {}

function M.setup(user_config)
  M.options = vim.tbl_deep_extend("force", default_config, user_config or {})
  return M.options
end

return M
