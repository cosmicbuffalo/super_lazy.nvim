-- Minimal init.lua for running tests with plenary

local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local super_lazy_dir = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":p:h:h")

vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(super_lazy_dir)

vim.cmd("runtime! plugin/plenary.vim")

-- Set up minimal lazy.nvim mock for testing
package.loaded["lazy.core.config"] = {
  options = { lockfile = "/tmp/lazy-lock.json" },
  plugins = {},
  spec = { disabled = {}, plugins = {} },
}

package.loaded["lazy.manage.git"] = {
  info = function(dir, refresh)
    return nil
  end,
  get_branch = function(plugin)
    return "main"
  end,
}

package.loaded["lazy.manage.lock"] = {
  update = function()
    -- Mock update function
  end,
}

package.loaded["lazy.util"] = {
  file_exists = function(path)
    return vim.fn.filereadable(path) == 1
  end,
  ls = function(dir, callback)
    -- Mock ls function
  end,
  read_file = function(path)
    return ""
  end,
}

package.loaded["lazy.pkg.rockspec"] = {
  deps = function(plugin)
    return nil
  end,
}

package.loaded["lazy.view.render"] = {
  details = function(self, plugin)
    -- Mock details function
  end,
}
