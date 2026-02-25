-- lua/perfnvim/setup.lua

local constants = require("perfnvim.constants")
local change_helpers = require("perfnvim.helpers.change_helpers")

local function setup()
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		pattern = "*",
		callback = change_helpers._AnnotateSigns,
	})
end

return {
	setup = setup,
}
