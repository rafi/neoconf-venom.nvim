# Venom: Neoconf

> Discover project's virtual-environment and automatically set LSP servers.

## Overview

Automatically find project's virtual-environment using various strategies:

- Searches for `venv`, `.venv`, `.python-version`
  - If directory, use as virtual-environment. Great for in-project environments.
  - If a file, read the first line as path. Good for pyenv/virtualenvwrapper
- Otherwise, use 3rd-party tools to find one:
  - `poetry env info -p`
  - `pipenv --venv`

Once found, register with LSP servers:

- pyright
- pylsp

Once installed and set-up, you can use `:Neoconf lsp` to view the applied
changes.

## Install

Requirements:

- [Neovim] ≥0.8
- [nvim-lspconfig]
- [neoconf.nvim]
- [plenary.nvim]

Use your favorite package-manager:

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">lazy.nvim</a></summary>

```lua
{
  'rafi/neoconf-venom.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  version = false,
},
```

</details>

<details>
<summary>With <a href="https://github.com/wbthomason/packer.nvim">packer.nvim</a></summary>

```lua
use {
  'rafi/neoconf-venom.nvim',
  requires = { 'nvim-lua/plenary.nvim' }
}
```

</details>

## Setup

It's important that you set up venom **AFTER** neoconf.nvim and **BEFORE**
nvim-lspconfig.

For example, using [lazy.nvim]:

```lua
{
  'neovim/nvim-lspconfig',
  event = { 'BufReadPre', 'BufNewFile' },
  dependencies = {
    { 'folke/neoconf.nvim', cmd = 'Neoconf', config = true },
    'rafi/neoconf-venom.nvim',
  },
  config = function(_, opts)
    -- …

    require('venom').setup()

    -- continue to setup lsp servers…
  end,
},

{
  'rafi/neoconf-venom.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'folke/neoconf.nvim' },
},
```

## Debug

Use `:Neoconf lsp` to view settings. For example:

```markdown
# Lsp Settings

## pyright

* ~/.config/nvim/neoconf.json 

{
  python = {
    analysis = {
      autoSearchPaths = true,
      diagnosticMode = "workspace",
      useLibraryCodeForTypes = true
    },
    pythonPath = "/Users/bob/.local/share/pyenv/versions/foo/bin/python"
  }
}
```

## Config

These are the default settings:

```lua
require('venom').setup({
  echo = true,
  symbol = '🐍',
  venv_patterns = { 'venv', '.venv', '.python-version' },
  use_tools = true,
  tools = {
    pipenv = { 'pipenv', '--venv' },
    poetry = { 'poetry', 'env', 'info', '-p' },
  },
  plugins = {
    pyright = function(venv_path)
      return {
        python = {
          pythonPath = table.concat({ venv_path, 'bin', 'python' }, '/')
        },
      }
    end,
    pylsp = function(venv_path)
      return {
        pylsp = {
          plugins = { jedi = { environment = venv_path } }
        },
      }
    end,
  },
})
```

## See More

[neoconf.nvim], [nvim-lspconfig]

[Neovim]: https://github.com/neovim/neovim
[nvim-lspconfig]: https://github.com/neovim/nvim-lspconfig
[neoconf.nvim]: https://github.com/folke/neoconf.nvim
[plenary.nvim]: https://github.com/nvim-lua/plenary.nvim
[lazy.nvim]: https://github.com/folke/lazy.nvim
