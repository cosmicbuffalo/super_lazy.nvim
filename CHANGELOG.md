# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of super_lazy.nvim
- Multi lockfile management for lazy.nvim
- Support for multiple plugin source repositories
- Plugin source detection in `**/plugins/**/*.lua` files
- Recipe plugin support (plugins defined in other plugins' lazy.lua files)
- UI integration showing plugin source in lazy.nvim interface
- Health check (`:checkhealth super_lazy`) for validating setup and version compatibility
- Smart caching for improved performance
- Modular codebase with separate modules for config, cache, lockfile, source, ui, and health
- Comprehensive API for programmatic access
- Error handling throughout the codebase

### Documentation
- Comprehensive README with usage examples
- API documentation
- Troubleshooting guide
- Contributing guidelines
- MIT License

## [1.0.0] - TBD

Initial stable release.

### Features
- Multi lockfile management
- Multi-repository plugin organization
- UI enhancements for lazy.nvim
- Compatible with lazy.nvim 11.17.1
