-- Neoconf-Venom
-- https://github.com/rafi/neoconf-venom.nvim

local M = {}

-- Make new picker and fetch virtualenvs.
---@private
---@param opts table
M._new_picker = function(opts)
	local actions = require('telescope.actions')
	local action_state = require('telescope.actions.state')
	local venom = require('venom')

	local virtualenvs = venom.find_python_runtimes()
	if not virtualenvs then
		return
	end

	local nicelist = {}
	for _, venv in ipairs(virtualenvs) do
		table.insert(nicelist, vim.fn.fnamemodify(venv, ':~'))
	end

	require('telescope.pickers').new(
		opts,
		require('telescope.themes').get_dropdown({
			layout_config = { width = 0.55, height = 0.45 },
			prompt_title = 'Virtualenvs',
			finder = require('telescope.finders').new_table({ results = nicelist }),
			sorter = require('telescope.config').values.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					if selection == nil then
						require('telescope.utils').__warn_no_selection('builtin.venom')
						return
					end
					actions.close(prompt_bufnr)
					require('venom').set_virtualenv(selection[1])
				end)
				return true
			end,
		})
	)
	:find()
end

--- Find virtual-environments.
---@param opts table
M.virtualenvs = function(opts)
	M._new_picker(opts)
end

return M
