# super_lazy.nvim

A Neovim plugin that extends [lazy.nvim](https://github.com/folke/lazy.nvim) to support **multiple lockfiles**, enabling separation of plugin configurations across multiple repositories.

## Features

- **Multi Lockfile Management**: Automatically maintain separate `lazy-lock.json` files for different plugin sources (e.g., shared team config vs. personal config)
- **Source Detection**: Intelligent detection of which repository each plugin belongs to
- **UI Integration**: Enhanced lazy.nvim UI showing the source repository for each plugin
- **Recipe/Package Support**: Handles plugins defined within other plugins' `lazy.lua` files
- **Health Check**: Built-in `:checkhealth super_lazy` for validating setup and version compatibility
- **Smart Caching**: Optimized performance through intelligent caching mechanisms

## Use Cases

- **Team Configurations**: Separate shared team plugins from personal ones
- **Dotfiles Management**: Keep work and personal configurations separate
- **Multi-Machine Setups**: Maintain different plugin sets for different environments
- **Monorepo Setups**: Manage plugins across multiple configuration repositories

## Requirements

- Neovim >= 0.8.0
- [lazy.nvim](https://github.com/folke/lazy.nvim) >= 11.17.5

## Installation

Install using lazy.nvim:

```lua
{
  "cosmicbuffalo/super_lazy.nvim",
  lazy = false,  -- Must be loaded immediately to hook into lazy.nvim
  opts = {
    -- add your list of repo root directories for lockfile management here
    lockfile_repo_dirs = {
      vim.fn.stdpath("config"),
      -- configure additional config repo paths here
    }
  }
}
```

## Usage example

If your config structure looks something like this:

```
~/.config/nvim/             (main config repo)
├── init.lua
├── lazy-lock.json          (auto-generated main repo lockfile)
└── lua/
    ├── personal/           (nested config repo)
    │   ├── lazy-lock.json  (auto-generated nested repo lockfile)
    │   └── plugins/
    │       └── foo.lua     (nested repo plugin spec)
    └── plugins/
        └── bar.lua         (main repo plugin spec)
```

Ensure that your lockfile repo dirs are set in your super_lazy plugin spec (see Installation above):
```lua
{
    lockfile_repo_dirs = {
        vim.fn.stdpath("config"),
        vim.fn.stdpath("config") .. "/lua/personal",
    }
}
```

And ensure that you are loading both plugin locations in your lazy setup:

```lua
-- Inside ~/.config/nvim/init.lua
-- refer to docs for lazy.nvim for full bootstrap setup
require("lazy").setup({
    spec = {
        { import = "plugins" },
        { import = "personal.plugins" },
    }
})
```

In the above configuration example, plugins that come from the nested `personal/` repo will be 
saved into the lockfile in that repo and plugins that come from the main config repo will be saved
into the lockfile at the root of the main config directory

## How It Works

1. **Hook Integration**: super_lazy.nvim hooks into lazy.nvim's lockfile update mechanism
2. **Source Detection**: When lazy.nvim updates, super_lazy determines which repository each plugin belongs to
3. **Lockfile Generation**: Separate lockfiles are written to each configured repository directory
4. **UI Enhancement**: The lazy.nvim UI is enhanced to show the source repository for each plugin

### Source Detection Logic

For each plugin, super_lazy.nvim:
1. Searches for plugin specifications in the configured `lockfile_repo_dirs`
2. Checks plugin files matching the pattern `**/plugins/**/*.lua`
3. For plugins defined in recipes/packages (other plugins' `lazy.lua` files), tracks the parent plugin
4. Assigns the plugin to the first matching repository

### Known Limitations

This plugin essentially works by piggybacking on top of the existing `lazy.nvim` plugin manager's functionality and stepping in after the main repo's lockfile has been updated by `lazy.nvim` to layer on logic around splitting the lockfile across multiple repos. Due to this, there are some known limitations in behavior of this plugin:

- `Lazy` expects one plugin to have one version
  - Plugins that exist in multiple config repos with different versions are not handled by Lazy - only the version in the main config repo will be visible to Lazy on restore, and only the installed version will be written to lockfiles on updates
- `Lazy` only reads the main config repo's lockfile for restore operations
  - For any plugins located in additional config repos, they will be updated to the latest commit on their configured branch during a restore operation instead of to the version in their respective config repo's lockfile

> [!NOTE]
> These limitations may be solveable by `super_lazy.nvim`, but the current state of this plugin does not address these limitations. 

## Troubleshooting

### Health Check

Run the health check to verify your setup:

```vim
:checkhealth super_lazy
```

This will check:
- Neovim version compatibility
- lazy.nvim installation and version
- Configuration validity
- Repository directory structure
- Plugin file detection

### Version Compatibility

super_lazy.nvim requires lazy.nvim version 11.17.5. Use `:checkhealth super_lazy` to verify your lazy.nvim version and get specific guidance if there's a mismatch.

### Plugin Not Found Error

If you get an error like:
```
Plugin 'plugin-name' not found in any configured lockfile repository
```

Ensure:
1. The plugin is defined in one of your `lockfile_repo_dirs`
2. The plugin file is in a `plugins/` directory
3. The plugin specification follows the correct format laid out by `lazy.nvim`'s [Plugin Spec](https://lazy.folke.io/spec)

### Clear Caches

If you experience unexpected behavior after configuration changes:

```lua
require("super_lazy.cache").clear_all()
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development

- Run tests: `make test` (requires plenary.nvim)
- Format code: `stylua lua/` (uses included stylua.toml)

## License

MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

- [lazy.nvim](https://github.com/folke/lazy.nvim) by [@folke](https://github.com/folke) - The excellent plugin manager this extends

## Support

- **Issues**: [GitHub Issues](https://github.com/cosmicbuffalo/super_lazy.nvim/issues)
- **Discussions**: [GitHub Discussions](https://github.com/cosmicbuffalo/super_lazy.nvim/discussions)
