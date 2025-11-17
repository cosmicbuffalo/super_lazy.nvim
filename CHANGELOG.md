# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.4] - 2025-11-17

### Fixed
- Disabled plugins that exist in config but are not installed now correctly restore their lockfile entries from git HEAD
  - Previously, disabled plugins would only restore if they existed in the current main lockfile
  - Now also checks the original lockfile from git HEAD as a fallback, ensuring disabled plugins remain in lockfiles when running `lazy restore`

## [0.2.3] - 2025-11-05

### Added
- **Git-based Lockfile Preservation**: New lockfile caching system that preserves plugin entries pre-Lazy operations from git HEAD
  - Reads original lockfile from `git show HEAD:lazy-lock.json` to restore entries for disabled plugins
  - Commit-based cache invalidation ensures cache stays in sync
  - Cache stored at `~/.local/share/nvim/super_lazy/original_lockfile.json`
- New lockfile API methods: `get_cached()` and `clear_cache()` for accessing git-based lockfile data

### Fixed
- Disabled plugins with nested recipe plugins now correctly preserve all entries even when parent is not installed
- Cache directory paths now use dynamic functions instead of constants for better test mocking support

## [0.2.2] - 2025-11-03

### Fixed
- Lockfile sync now detects when main lockfile has uncommitted changes, fixing cases where configured repo paths don't exist at initialization time

## [0.2.1] - 2025-10-15

### Added
- Persistent cache (`~/.cache/nvim/super_lazy/plugin_sources.json`) for plugin source mappings
- Timestamp-based lockfile sync detection for bootstrap scenarios
- `setup-plenary` Makefile target for automatic test dependency setup
- Test coverage for timestamp sync detection and persistent cache

### Changed
- Startup now near-instant using persistent cache instead of file system searches
- UI hooks load on-demand when Lazy UI opens
- Reduced public API to: `setup()`, `write_lockfiles()`, `setup_lazy_hooks()`

## [0.2.0] - 2025-10-15

### Added
- **Recipe Plugin Metadata**: Added `source` field to lockfile entries for recipe plugins (plugins defined in lazy.lua files of other plugins), tracking parent-child relationships
- **Clean Operation**: Added hooks into lazy.nvim clean operation to restore lockfile entries for plugins still in config but cleaned from disk
- **Initial Install Support**: Lockfiles are now updated asynchronously after plugin setup to handle plugins installed before super_lazy loads, fixing issues with initial lazy.nvim install operations
- **Headless Execution Test**: Added test coverage to ensure headless nvim commands don't hang or timeout

### Changed
- **Enhanced Source Detection**: `get_plugin_source()` now returns both repository path and parent plugin name when requested, enabling better recipe plugin tracking
- **Disabled Plugin Preservation**: Disabled plugins now correctly remain in lockfiles with their commit information preserved
- **Nested Plugin Preservation**: When a recipe plugin (parent) is disabled, its nested child plugins are now correctly preserved in lockfiles as long as the parent exists

## [0.1.1] - 2025-10-14

Hotfix for minor bug

## [0.1.0] - 2025-10-14

Initial release of super_lazy.nvim - A Neovim plugin that extends lazy.nvim to support multiple lockfiles across multiple configuration repositories.

### Features

#### Core Functionality
- **Multiple Lockfile Management**: Automatically maintain separate `lazy-lock.json` files for different plugin sources (e.g., shared team config vs. personal config)
- **Intelligent Source Detection**: Automatically detects which repository each plugin belongs to by scanning `**/plugins/**/*.lua` files
- **Recipe Plugin Support**: Handles plugins defined within other plugins' `lazy.lua` files, tracking parent-child relationships
- **Automatic Hook Integration**: Seamlessly hooks into lazy.nvim's lockfile update mechanism
- **Smart Caching**: Optimized performance with intelligent caching of paths, plugin existence checks, recipes, and git information

#### User Interface
- **Enhanced lazy.nvim UI**: Shows the source repository for each plugin in the lazy.nvim interface
- **Source Display with Recipe Info**: Displays parent plugin information for recipe-based plugins

#### Developer Experience
- **Health Check**: Comprehensive `:checkhealth super_lazy` command that validates:
  - Neovim version compatibility (>= 0.8.0)
  - lazy.nvim installation and version (11.17.1)
  - Configuration validity
  - Repository directory structure
  - Plugin file detection
- **Error Handling**: Robust error handling with graceful fallbacks throughout the codebase
- **Modular Architecture**: Separation of concerns with dedicated modules:
  - `config` - Configuration management
  - `cache` - Caching layer for performance
  - `lockfile` - Lockfile read/write operations
  - `source` - Plugin source detection logic
  - `ui` - UI integration with lazy.nvim
  - `health` - Health check implementation
  - `util` - Shared utilities

### Documentation
- Comprehensive README with installation instructions and usage examples
- Detailed configuration examples for team and personal plugin separation
- Troubleshooting guide with common issues and solutions
- Contributing guidelines for developers
- MIT License

### Testing
- Unit tests covering all modules
- Integration tests for multi-lockfile writing
- Error handling and edge case coverage
- CI/CD workflow for automated testing

### Compatibility
- **Neovim**: >= 0.8.0
- **lazy.nvim**: 11.17.1 (exact version required)

### Notes
This is the first release. The plugin is still a work in progress. Please report any issues on the [GitHub Issues](https://github.com/cosmicbuffalo/super_lazy.nvim/issues) page.
