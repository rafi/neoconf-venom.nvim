-- Neoconf-Venom
-- https://github.com/rafi/neoconf-venom.nvim

local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
	error('This feature requires nvim-telescope/telescope.nvim')
end

local config = {
	mappings = {},
}

-- Setup extension config
local setup = function(opts)
	config.mappings =
		vim.tbl_deep_extend('force', config.mappings, require('telescope.config').values.mappings)
	config = vim.tbl_deep_extend('force', config, opts)
end

-- Sub-commands
local virtualenvs = require('telescope._extensions.venom.virtualenvs').virtualenvs

-- Register plugin
return telescope.register_extension({
	setup = setup,
	exports = {
		virtualenvs = virtualenvs,
	},
})

