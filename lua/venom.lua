-- venom: discover venv and automatically set LSP servers
-- https://github.com/rafi/neoconf-venom.nvim

local is_windows = vim.loop.os_uname().version:match('Windows')
local Util = require('neoconf.util')
local has_plenary, Job = pcall(require, 'plenary.job')
if not has_plenary then
	Util.error('venom requires https://github.com/nvim-lua/plenary.nvim')
	return
end
local Path = require('plenary.path')

local M = {}

---@type VenomConfig
local opts = {}

---@type table<string, string>
local cached_venvs = {}

---@type table<string, boolean>
local cached_unresolved_paths = {}

---@param filename string
---@return boolean
local function is_dir(filename)
	return Util.exists(filename) == 'directory'
end

---@class VenomConfig
local default_opts = {
	echo = true,
	symbol = '🐍',
	venv_patterns = { 'venv', '.venv', '.python-version' },
	use_tools = true,
	tools = {
		pipenv = { 'pipenv', '--venv' },
		poetry = { 'poetry', 'env', 'info', '-p' },
		hatch = { 'hatch', 'env', 'find' },
	},
	venv_locations = {
		(vim.env['PYENV_ROOT'] or vim.loop.os_homedir()..'/.pyenv') .. '/versions',
		vim.env['WORKON_HOME'],
	},
	---@type table<string, fun(venv_path:string):table>
	plugins = {
		--- pyright
		---@param venv_path string
		---@return table
		pyright = function(venv_path)
			if is_dir(venv_path) then
				venv_path = table.concat({ venv_path, 'bin', 'python' }, '/')
			end
			return {
				python = { pythonPath = venv_path },
			}
		end,

		--- pylsp
		---@param venv_path string
		---@return table
		pylsp = function(venv_path)
			return {
				pylsp = { plugins = { jedi = { environment = venv_path } } },
			}
		end,
	},
}

---@param filename string
---@return boolean
local function is_absolute(filename)
	if is_windows then
		return filename:match('^%a:') or filename:match('^\\\\')
	else
		return filename:match('^/')
	end
end

---@param ... string
---@return string
local function path_join(...)
	return table.concat(vim.tbl_flatten { ... }, '/')
end

--- Verifies python executable exists in a venv.
---@param venv_path string
---@return boolean
local function is_venv(venv_path)
	if venv_path == '' or venv_path == nil then
		return false
	end
	local bin = path_join(venv_path, 'bin', 'python')
	return is_dir(venv_path) and Util.exists(bin)
end

--- Checks if a path is a subdirectory of another path.
-- @tparam child
-- @tparam parent
-- @treturn boolean
local function is_subdirectory(child, parent)
	local child_parts = vim.split(child, "/", {})
	local parent_parts = vim.split(parent, "/", {})

	if #child_parts <= #parent_parts then
		return false
	end

	for i, part in ipairs(parent_parts) do
		if child_parts[i] ~= part then
			return false
		end
	end

	return true
end

-- Use predefined executables to find virtualenv's location.
---@return string
local function find_with_tools()
	for _, cmd in pairs(vim.deepcopy(opts.tools)) do
		if type(cmd) ~= 'table' then
			Util.error('[venom] tools value has to be a table')
			return ''
		end

		local command = table.remove(cmd, 1)
		local stderr = {}

		if vim.fn.executable(command) == 1 then
			local stdout, ret = Job:new({
				command = command,
				args = cmd,
				on_stderr = function(_, data)
					table.insert(stderr, data)
				end,
			}):sync()

			if ret == 0 then
				if is_venv(stdout[1]) then
					return stdout[1]
				end
			end
			if #stderr > 0 then
				Util.error(
					string.format('Erroneous shell output from %s: %s',
						command, vim.inspect(stderr))
				)
			end
		end
	end
	return ''
end

-- Finds a virtual-environment by using multiple strategies for provided
-- project path:
-- Searches for {venv, .venv, .python-version} and:
--   a. If directory, use as virtual-environment. Great for in-project venv/
--   b. If a file, read the first line as path. Good for pyenv/virtualenvwrapper
---@param path string
---@return string
local function find_virtualenv(path)
	local venv_locations = {}
	for _, dir in ipairs(opts.venv_locations) do
		if Util.exists(dir) then
			table.insert(venv_locations, dir)
		end
	end

	-- Try to find certain directory names or placeholder text files that
	-- are probably the virtual-environment we're looking for.
	local found_paths = vim.fs.find(opts.venv_patterns, {
		upward = true,
		stop = vim.loop.os_homedir(),
		path = path,
		limit = 3,
	})

	-- Return first found match.
	for _, found_path in ipairs(found_paths) do
		if found_path == nil or found_path == '' then
			-- skip
		elseif is_venv(found_path) then
			return found_path
		elseif Util.exists(found_path) == 'file' then
			-- Read location of virtual-environment from text-file
			local user_dir = Path:new(found_path):head(1)
			if not (user_dir == nil or user_dir == '') then
				-- Use file contents as an absolute path
				if is_absolute(user_dir) and is_venv(found_path) then
					return user_dir
				end
				-- Use file contents as a pyenv/virtualenvwrapper version
				for _, venv_location in ipairs(venv_locations) do
					venv_location = path_join(venv_location, user_dir)
					if is_venv(venv_location) then
						return venv_location
					end
				end
			end
		end
	end
	return ''
end

---@param venv_path string
---@param setter fun(venv_path:string):table
---@param client lsp.Client
---@return boolean
local function apply_function(venv_path, setter, client)
	local new_config = setter(venv_path)
	if not vim.tbl_isempty(new_config) then
		Util.merge(client.config.settings, new_config)
		local ok = pcall(client.notify, 'workspace/didChangeConfiguration', {
			settings = nil,
			-- settings = new_config,
		})
		return ok
	end
	return false
end

-- Update LSP configurations for various Venom plugins.
---@param client lsp.Client
---@param venv_path string
local function apply_venom_plugins(client, venv_path)
	for lsp_name, setter in pairs(opts.plugins) do
		if client.name == lsp_name then
			local msg = vim.fn.fnamemodify(venv_path, ':~')
			if apply_function(venv_path, setter, client) then
				if opts.echo then
					local title = 'Virtual-environment set (' .. lsp_name .. ')'
					vim.notify(msg, vim.log.levels.INFO, { title = title })
				end
			else
				local title = 'Failed setting virtual-environment (' .. lsp_name .. ')'
				vim.notify(msg, vim.log.levels.ERROR, { title = title })
			end
		end
	end
end

-- On init hook for LSP clients. Automatically sets found virtualenv path.
---@param root_dir string
---@return fun(lsp.Client):boolean
local function lsp_client_on_init(root_dir)
	return function(client)
		-- First look in cached paths.
		if cached_venvs[root_dir] ~= nil then
			apply_venom_plugins(client, cached_venvs[root_dir])
			return true
		end
		if cached_unresolved_paths[root_dir] == true then
			return false
		end

		-- Find virtualenv's python binary with multiple methods.
		local venv_path = find_virtualenv(root_dir)
		if venv_path == '' or not is_dir(venv_path) then
			if opts.use_tools then
				-- Use predefined executables to find virtualenv's location.
				venv_path = find_with_tools()
			end
			if venv_path == '' or not is_dir(venv_path) then
				cached_unresolved_paths[root_dir] = true
				return false
			end
		end

		-- Cache and update LSP clients with found venv python binary.
		cached_venvs[root_dir] = venv_path
		vim.api.nvim_buf_set_var(0, 'virtual_env', venv_path)
		apply_venom_plugins(client, venv_path)
		return true
	end
end

--- Set virtualenv in active LSP clients.
---@param virtualenv string virtual-environment path
---@param cwd string? root directory of project
function M.set_virtualenv(virtualenv, cwd)
	cwd = cwd or vim.loop.cwd() or vim.fn.getcwd()
	cached_venvs[cwd] = virtualenv

	local clients = vim.lsp.get_active_clients()
	for _, client in ipairs(clients) do
		apply_venom_plugins(client, virtualenv)
	end
end

-- Finds virtualenvs in the system, also using pyenv, and returns a list.
---@return table|nil
function M.find_python_runtimes()
	if is_windows then
		vim.notify('Error: Doesn\'t work on Windows yet.', vim.log.levels.ERROR)
		return
	end

	local venvs = {}
	local stderr = {}

	local stdout, ret = Job:new({
		command = 'which',
		args = { '-a', 'python', 'python3' },
		on_stderr = function(_, data)
			table.insert(stderr, data)
		end,
	}):sync()

	if ret == 0 then
		for _, venv in ipairs(stdout) do
			table.insert(venvs, venv)
		end
	else
		Util.error(string.format('Erroneous shell output: %s', vim.inspect(stderr)))
		return
	end

	if vim.fn.executable('pyenv') == 1 then
		stdout, ret = Job:new({
			command = 'pyenv',
			args = { 'root' },
			on_stderr = function(_, data)
				table.insert(stderr, data)
			end,
		}):sync()

		if ret == 0 then
			local pyenv_root = stdout[1]
			local versions = vim.fn.globpath(pyenv_root, 'versions/*/bin/python', 0, 1)
			for _, venv in ipairs(versions) do
				table.insert(venvs, venv)
			end
		end
	end

	if #stderr > 0 then
		Util.error(string.format('Erroneous shell output: %s', vim.inspect(stderr)))
	end
	return venvs
end

-- Setup LSP on_init hooks as Neoconf plugin.
---@param plugin_name string
---@return fun()
local function setup_neoconf_plugin(plugin_name)
	return function()
		Util.on_config({
			name = 'settings/plugins/' .. plugin_name,
			on_config = function(client, root_dir)
				if client.name == plugin_name then
					client.on_init = lsp_client_on_init(root_dir)
				end
			end,
		})
	end
end

--- Statusline friendly Venom section.
---@return string
function M.statusline()
	local venv_path = vim.b['virtual_env'] or vim.env.VIRTUAL_ENV
	if not (venv_path == nil or venv_path == '') then
		return vim.fs.basename(venv_path) .. ' ' .. opts.symbol
	end
	return ''
end

-- Setup Venom: Register as neoconf plugins.
---@param user_opts? table
function M.setup(user_opts)
	opts = Util.merge({}, default_opts, user_opts or {})
	vim.validate({
		echo = { opts.echo, 'b', true },
		symbol = { opts.symbol, 's', true },
		venv_patterns = { opts.venv_patterns, 't', true },
		use_tools = { opts.use_tools, 'b', true },
		tools = { opts.tools, 't', true },
	})

	-- Register Neoconf plugins.
	for lsp_name, _ in pairs(opts.plugins) do
		require('neoconf.plugins').register({
			setup = setup_neoconf_plugin(lsp_name),
		})
	end
end

return M
