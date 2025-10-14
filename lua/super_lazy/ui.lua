local Source = require("super_lazy.source")
local Util = require("super_lazy.util")

local M = {}

-- This function is a direct copy of the internals of lazy.view.render.details
local function insert_lazy_props(self, props, plugin)
  local LazyGit = require("lazy.manage.git")
  local LazyUtil = require("lazy.util")

  table.insert(props, { "dir", plugin.dir, "LazyDir" })
  if plugin.url then
    table.insert(props, { "url", (plugin.url:gsub("%.git$", "")), "LazyUrl" })
  end

  local git = LazyGit.info(plugin.dir, true)
  if git then
    git.branch = git.branch or LazyGit.get_branch(plugin)
    if git.version then
      table.insert(props, { "version", tostring(git.version) })
    end
    if git.tag then
      table.insert(props, { "tag", git.tag })
    end
    if git.branch then
      table.insert(props, { "branch", git.branch })
    end
    if git.commit then
      table.insert(props, { "commit", git.commit:sub(1, 7), "LazyCommit" })
    end
  end

  local rocks = require("lazy.pkg.rockspec").deps(plugin)
  if rocks then
    table.insert(props, { "rocks", vim.inspect(rocks) })
  end

  if LazyUtil.file_exists(plugin.dir .. "/README.md") then
    table.insert(props, { "readme", "README.md" })
  end
  LazyUtil.ls(plugin.dir .. "/doc", function(path, name)
    if name:sub(-3) == "txt" then
      local data = LazyUtil.read_file(path)
      local tag = data:match("%*(%S-)%*")
      if tag then
        table.insert(props, { "help", "|" .. tag .. "|" })
      end
    end
  end)

  for handler in pairs(plugin._.handlers or {}) do
    table.insert(props, {
      handler,
      function()
        self:handlers(plugin, handler)
      end,
    })
  end
end

function M.setup_hooks()
  local ok, err = pcall(function()
    local render = require("lazy.view.render")
    local original_details = render.details

    render.details = function(self, plugin)
      -- Wrap custom logic in error handling, fall back to original if it fails
      local custom_ok, custom_err = pcall(function()
        -- Build props array like the original function does
        local props = {}

        -- Add our source information at the top
        local source_info = "unknown"
        local source_ok, result = pcall(Source.get_plugin_source, plugin.name, true)
        if source_ok then
          source_info = result
        end
        table.insert(props, { "source", source_info, "LazyReasonEvent" })

        -- Put in all the same properties as the original details function
        insert_lazy_props(self, props, plugin)

        self:props(props, { indent = 6 })
        self:nl()
      end)

      if not custom_ok then
        -- Fall back to original details function if custom details logic fails
        Util.notify("Error in UI details hook: " .. tostring(custom_err), vim.log.levels.WARN)
        original_details(self, plugin)
      end
    end
  end)

  if not ok then
    Util.notify("Failed to setup UI hooks: " .. tostring(err), vim.log.levels.WARN)
  end
end

return M
