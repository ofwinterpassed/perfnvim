-- lua/perfnvim/setup.lua

local constants = require("perfnvim.constants")
local change_helpers = require("perfnvim.helpers.change_helpers")

local function setup()
	local green = vim.api.nvim_get_hl(0, { name = "Added" }).fg
	vim.api.nvim_set_hl(0, constants.p4addSignHighlight, { fg = green, bg = "NONE" })
	vim.fn.sign_define(constants.p4addSignName, {
		text = "▐",
		texthl = constants.p4addSignHighlight,
	})

	local yellow = vim.api.nvim_get_hl(0, { name = "Changed" }).fg
	vim.api.nvim_set_hl(0, constants.p4changeSignHighlight, { fg = yellow, bg = "NONE" })
	vim.fn.sign_define(constants.p4changeSignName, {
		text = "▐",
		texthl = constants.p4changeSignHighlight,
	})

	local red = vim.api.nvim_get_hl(0, { name = "Removed" }).fg
	vim.api.nvim_set_hl(0, constants.p4deleteSignHighlight, { fg = red, bg = "NONE" })
	vim.fn.sign_define(constants.p4deleteSignName, {
		text = "▐",
		texthl = constants.p4deleteSignHighlight,
	})
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		pattern = "*",
		callback = change_helpers._AnnotateSigns,
	})
end

return {
	setup = setup,
}
