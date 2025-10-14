# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
