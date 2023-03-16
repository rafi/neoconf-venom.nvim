-- venom: discover venv and automatically set LSP servers
-- https://github.com/rafi/vim-config

local Path = require('lspconfig.util').path
local Util = require('neoconf.util')

local opts = {}

local default_opts = {
	auto_activate = true,
	echo = true,
	quiet = false,
	symbol = '🐍',
	root_patterns = { 'venv', '.venv', '.python-version' },
	use_tools = true,
	tools = {
		poetry = 'poetry env info -p',
		pipenv = 'pipenv --venv',
	},
}

-- Will contain root directories as keys, and found venv python bin path
-- as the value. For example: { '/home/foo/bar' = '/home/foo/bar/venv' }
local cached_venvs = {}
local cached_unresolved_paths = {}

-- Supported LSP plugins setters.
local lsp_plugins = {
	pyright = function(venv_path)
		local venv_python_path = Path.join(venv_path, 'bin', 'python')

		return {
			python = {
				pythonPath = venv_python_path
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
}

-- Find files/directories in a specific path.
---@param path string
---@param patterns table
local function find_pattern(path, patterns)
	for _, pattern in ipairs(patterns) do
		local path_joined = Path.join(path, pattern)
		for _, p in ipairs(vim.fn.glob(path_joined, true, true)) do
			if Path.exists(p) then
				return p
			end
		end
	end
end

-- Finds a virtual-environment by using multiple strategies for provided
-- project path:
-- 1. Searches for {venv, .venv, .python-version} and:
--   a. If directory, use as virtual-environment. Great for in-project venv/
--   b. If a file, read the first line as path. Good for pyenv/virtualenvwrapper
-- 2. Use external tools:
--   a. poetry
--   b. pipenv
---@param path string
local function find_virtualenv(path)
	local pyenv_root = vim.env['PYENV_ROOT']
	local workon_home = vim.env['WORKON_HOME']

	-- Try to find certain directory names or placeholder text files that
	-- are probably the virtual-environment we're looking for.
	local found_path = find_pattern(path, opts.root_patterns)
	if not (found_path == nil or found_path == '') then
		if Path.is_dir(found_path) then
			return found_path
		elseif Path.is_file(found_path) then
			-- Read location of virtual-environment from text-file
			local file = io.open(found_path)
			local user_dir = ''
			if file ~= nil then
				user_dir = file:read('*l')
				file:close()
			end
			if not (user_dir == nil or user_dir == '') then
				-- Use file contents as an absolute path
				if Path.is_absolute(user_dir) and Path.is_dir(user_dir) then
					return user_dir
				end
				-- Use file contents as a pyenv version
				local pyenv_version = Path.join(pyenv_root, 'versions', user_dir)
				if pyenv_version ~= '' and Path.is_dir(pyenv_version) then
					return pyenv_version
				end
				-- Use file contents as a virtualenvwrapper directory
				local workon_dir = Path.join(workon_home, user_dir)
				if workon_dir ~= '' and Path.is_dir(workon_dir) then
					return workon_dir
				end
			end
		end
	end

	-- Use predefined executables to find virtualenv's location.
	-- TODO:
	return ''
end

-- Update LSP configurations for various plugins.
---@param client lsp.Client
---@param venv_path string
local function update_client_python_path(client, venv_path)
	for lsp_name, setter in pairs(lsp_plugins) do
		if client.name == lsp_name then
			local new_config = setter(venv_path)
			Util.merge(client.config.settings, new_config)
			local ok = pcall(client.notify, 'workspace/didChangeConfiguration', {
				settings = new_config,
			})
			local msg = vim.fn.fnamemodify(venv_path, ':~')
			if ok then
				if opts.echo then
					vim.notify(msg, vim.log.levels.INFO, {
						title = 'Virtual-environment set (' .. lsp_name .. ')'
					})
				end
			else
				vim.notify(msg, vim.log.levels.ERROR, {
					title = 'Failed setting virtual-environment (' .. lsp_name .. ')'
				})
			end
		end
	end
end

-- On init hook for LSP clients. Automatically sets found virtualenv path.
---@param root_dir string
local function on_init(root_dir)
	return function(client)
		-- First look in cached paths.
		if cached_venvs[root_dir] ~= nil then
			update_client_python_path(client, cached_venvs[root_dir])
			return true
		end
		if cached_unresolved_paths[root_dir] == true then
			return
		end

		-- Find virtualenv's python binary with multiple methods.
		local venv_path = find_virtualenv(root_dir)
		if venv_path == '' or not Path.is_dir(venv_path) then
			cached_unresolved_paths[root_dir] = true
			return
		end

		-- Cache and update LSP clients with found venv python binary.
		cached_venvs[root_dir] = venv_path
		vim.api.nvim_buf_set_var(0, 'virtual_env', venv_path)
		update_client_python_path(client, venv_path)
		return true
	end
end

---@param path string
local function basename(path)
	return string.gsub(path, '(.*/)(.*)', '%2')
end

local function statusline()
	local venv_path = vim.b['virtual_env'] or os.getenv('VIRTUAL_ENV')

	if not (venv_path == nil or venv_path == '') then
		return basename(venv_path) .. ' ' .. opts.symbol
	end
	return ''
end

-- Setup LSP on_init hooks as Neoconf plugin.
---@param plugin_name string
local function setup_plugin(plugin_name)
	return function()
		Util.on_config({
			name = 'settings/plugins/' .. plugin_name,
			on_config = function(client, root_dir)
				if client.name == plugin_name then
					client.on_init = on_init(root_dir)
				end
			end,
		})
	end
end

-- Setup Venom
---@param user_opts? table
local function setup(user_opts)
	opts = Util.merge({}, default_opts, user_opts or {})
	vim.validate({
		auto_activate = { opts.auto_activate, 'b', true },
		echo = { opts.echo, 'b', true },
		quiet = { opts.quiet, 'b', true },
		symbol = { opts.symbol, 's', true },
		root_patterns = { opts.root_patterns, 't', true },
		use_tools = { opts.use_tools, 'b', true },
		tools = { opts.tools, 't', true },
	})

	-- Register Neoconf plugins.
	for lsp_name, _ in pairs(lsp_plugins) do
		require('neoconf.plugins').register({
			setup = setup_plugin(lsp_name),
		})
	end
end

return {
	setup = setup,
	statusline = statusline,
}
