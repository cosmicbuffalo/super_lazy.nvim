local ui = require("super_lazy.ui")

describe("ui module", function()
  describe("setup_hooks", function()
    it("should be a function", function()
      assert.is_function(ui.setup_hooks)
    end)

    it("should not error when called", function()
      -- This test verifies that setup_hooks can be called without crashing
      -- The actual hook setup requires lazy.nvim's render module which is mocked
      assert.has_no.errors(function()
        ui.setup_hooks()
      end)
    end)

    it("should handle missing lazy.view.render gracefully", function()
      -- Save original require
      local original_require = require

      -- Mock require to fail for lazy.view.render
      _G.require = function(name)
        if name == "lazy.view.render" then
          error("Module not found")
        end
        return original_require(name)
      end

      -- Should not throw error due to pcall protection
      assert.has_no.errors(function()
        ui.setup_hooks()
      end)

      -- Restore original require
      _G.require = original_require
    end)

    it("should hook into lazy.view.render.details", function()
      local original_require = require
      local render_module_accessed = false
      local details_function_replaced = false

      _G.require = function(name)
        if name == "lazy.view.render" then
          render_module_accessed = true
          return {
            details = function(self, plugin)
              -- Original details function
            end,
          }
        end
        return original_require(name)
      end

      ui.setup_hooks()

      _G.require = original_require

      -- The module should have been accessed
      assert.is_true(render_module_accessed)
    end)
  end)
end)
