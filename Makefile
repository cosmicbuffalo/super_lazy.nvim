.PHONY: test format lint clean

# Test with plenary
test:
	@echo "Running tests with plenary.nvim..."
	@PLENARY_DIR=/tmp/plenary.nvim nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/spec', { minimal_init = 'tests/minimal_init.lua' })"

# Format code with stylua
format:
	@echo "Formatting Lua files with stylua..."
	@stylua lua/ tests/

# Lint with selene (if available)
lint:
	@echo "Linting Lua files..."
	@if command -v selene >/dev/null 2>&1; then \
		selene lua/; \
	else \
		echo "selene not found, skipping linting"; \
	fi

# Clean test artifacts
clean:
	@echo "Cleaning test artifacts..."
	@rm -rf /tmp/lazy-lock.json
	@rm -rf tests/plenary/

# Run all checks
check: format lint test
	@echo "All checks completed!"
