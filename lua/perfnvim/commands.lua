local M = {}
local client_helpers = require("perfnvim.helpers.client_helpers")
local file_helpers = require("perfnvim.helpers.file_helpers")
local helpers = require("perfnvim.helpers.other_helpers")

-- Function to list changelists and allow selection
function M.SelectChangelistInteractively(action)
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		print("Cannot add/edit file to a changelist: no file associated with the current buffer.")
		return
	end
	if vim.g.selected_changelist_win then
		local cmd = string.format("p4 " .. action .. " -c %s %s", vim.g.selected_changelist_win, filepath)
		vim.cmd("!" .. cmd)
		return
	end

	-- Get all the different changelist numbers in current client
	-- Alternative commands (1 preferred):
	-- 1 : p4 changelists -s pending -c <clientname> | cut -d' ' -f2
	-- 2 : p4 opened -s | cut -d' ' -f5 | uniq
    local handle = io.popen("p4 changelists -s pending -c " .. client_helpers._GetClientName())
	if not handle then
		print("Failed to run p4 changelists command")
		return
	end
	local result = handle:read("*a")
	handle:close()

	-- Pattern to match change number and description
	local pattern = "Change (%d+) on .- '%s*(.-)%s*'"

	-- Get description for all the changelist numbers
	local changelists = {}
	for change_number, description in result:gmatch(pattern) do
		table.insert(changelists, string.format("- Change %s: %s", change_number, description))
	end

	-- Also allow to create a new changelist
	table.insert(changelists, string.format("New..."))

	-- Create a new buffer and window for displaying changelists
	local newbuf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(newbuf, 0, -1, false, changelists)

	-- Define window options
	local width = 120
	local height = 3 * #changelists
	local opts = {
		relative = "editor",
		width = width,
		height = math.min(height, 20), -- Limit height to avoid overly large windows
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = "single",
	}

	local win = vim.api.nvim_open_win(newbuf, true, opts)

	-- Map <Enter> to select a changelist
	vim.api.nvim_buf_set_keymap(
		newbuf,
		"n",
		"<CR>",
		":lua select_changelist_entry()<CR>",
		{ noremap = true, silent = true }
	)

	-- Function to handle selection
	_G.select_changelist_entry = function()
		local line = vim.api.nvim_get_current_line()
		local changelist = line:match("Change (%d+)")
		if changelist then
			-- Run p4 add with the selected changelist
			local cmd = string.format("p4 " .. action .. " -c %s %s", changelist, filepath)
			print("cmd: " .. cmd)
			vim.cmd("!" .. cmd)
			vim.api.nvim_win_close(win, true)
		elseif line:match("New...") then
			-- Clear the buffer
			vim.api.nvim_buf_set_lines(
				newbuf,
				0,
				-1,
				false,
				{ "Write new changelist description. Press enter in normal mode when done." }
			)
			-- Enter insert mode
			vim.api.nvim_command("startinsert")
			-- Map <Enter> to create a new changelist with the entered description
			vim.api.nvim_buf_set_keymap(
				newbuf,
				"n",
				"<CR>",
				":lua create_new_changelist()<CR>",
				{ noremap = true, silent = true }
			)
		else
			print("Error: you did not select a valid line.")
		end
	end

	-- Function to create a new changelist
	_G.create_new_changelist = function()
		-- Get the description entered by the user
		local description = table.concat(vim.api.nvim_buf_get_lines(newbuf, 0, -1, false), "\n")

		if description and description ~= "" then
			-- Create a temporary file to hold the changelist form
			local tmpfile = os.tmpname()

			local p4ChangeHandle = io.popen("p4 change -o")
			if not p4ChangeHandle then
				print("Failed to run p4 change -o command")
				return
			end
			local changelist_form = p4ChangeHandle:read("*a")
			p4ChangeHandle:close()

			-- Modify the changelist form with the desired description
			changelist_form = changelist_form:gsub("(<enter description here.-)\n", description .. "\n")

			-- Write the modified form to the temporary file
			local file = io.open(tmpfile, "w")
			if not file then
				print("Error creating new changelist")
				return
			end
			file:write(changelist_form)
			file:close()

			-- Submit the changelist using the modified form
			local submit_handle = io.popen("p4 change -i < " .. tmpfile)
			if not submit_handle then
				print("Error executing p4 change -i")
				return
			end
			local p4ChangeIResult = submit_handle:read("*a")
			submit_handle:close()

			-- Clean up the temporary file
			os.remove(tmpfile)

			-- Close the window
			vim.api.nvim_win_close(win, true)

			-- Add/edit the file to the created changelist
			local changelist = p4ChangeIResult:match("Change (%d+) created.")
			if changelist then
				local cmd = string.format("p4 " .. action .. " -c %s %s", changelist, filepath)
				print("!cmd: " .. cmd)
				vim.cmd("!" .. cmd)
			else
				print("Failed to create changelist")
			end
		else
			print("No description entered. Aborting creation of new changelist.")
		end
	end
end

local function short_path(path)
  local folders = {}
  for folder in path:gmatch("[^/]+") do
	table.insert(folders, folder)
  end
  if #folders > 4 then
	return "..." .. "/" .. table.concat(folders, "/", #folders - 3, #folders)
  else
	return path
  end
end

local function _GetOpenedFilesData()
  if vim.g.perfnvim_enable == false then
    local opened_paths = file_helpers._GetP4OpenedPaths()
    if opened_paths == nil then
      print("No p4 opened files (or P4 connection failed)")
      return nil
    end

    local opened_files = {}
    for _, file in ipairs(opened_paths) do
      opened_files[file[1]] = { file[2], file[3] }
    end

    local opened_files_info = {}
    for file, file_info in pairs(opened_files) do
      local type = file_info[1]
      local chlist = file_info[2]
      local relative_path = file:gsub("^" .. vim.g.perfnvim_client_root .. "/", "")
      table.insert(opened_files_info, {
        full_path = file,
        relative_path = relative_path,
        changelist = chlist,
        type = type
      })
    end
    vim.g.perfnvim_p4_opened_files = opened_files_info
  end

  return vim.g.perfnvim_p4_opened_files
end

function M.GetP4Opened_Telescope()
  local actions = require("telescope.actions")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values

  local opened_files = _GetOpenedFilesData()
  if not opened_files then return nil end

  pickers
      .new({}, {
        finder = finders.new_table({
          results = opened_files,
          entry_maker = function(entry)
            return {
              value = entry.full_path,
              display = entry.changelist .. " -> " .. short_path(entry.relative_path),
              ordinal = entry.changelist .. " -> " .. short_path(entry.relative_path),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(_, map)
          map("i", "<CR>", actions.select_default)
          map("n", "<CR>", actions.select_default)
          return true
        end,
      })
      :find()
end

function M.GetP4Opened_Mini()
  local opened_files = _GetOpenedFilesData()
  if not opened_files then return nil end

  local items = {}
  for _, entry in ipairs(opened_files) do
    table.insert(items, {
      text = entry.changelist .. " -> " .. short_path(entry.relative_path),
      full_path = entry.full_path,
    })
  end

  require("mini.pick").start({
    source = {
      items = items,
      name = "P4 Opened Files",
      choose = function(item)
        if item then
          vim.cmd("edit " .. vim.fn.fnameescape(item.full_path))
        end
      end,
    },
  })
end

function M.GetP4Opened_Snacks()
  local opened_files = _GetOpenedFilesData()
  if not opened_files then return nil end

  local items = {}
  for _, entry in ipairs(opened_files) do
    table.insert(items, {
      text = entry.changelist .. " -> " .. short_path(entry.relative_path),
      file = entry.full_path,
    })
  end

  Snacks.picker.pick({
    source = "p4_opened",
    items = items,
    format = "{text}",
    on_confirm = function(item)
      if item then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      end
    end,
  })
end

function M.GetP4Opened()

  local backends = {
    telescope = M.GetP4Opened_Telescope,
    mini = M.GetP4Opened_Mini,
    snacks = M.GetP4Opened_Snacks,
  }

  local picker_fn = backends[vim.g.perfnvim_picker_backend]
  if not picker_fn then
    error("Unknown picker backend: " .. picker_backend)
  end

  return picker_fn()
end

function M.GoToPreviousChange()
	local buf = vim.fn.bufnr()
	local p4signs = {}
	local pattern = "^p4signs/.*"

	-- Get all sign groups
	local signs = vim.fn.sign_getplaced(buf, { group = '*' })

	-- Filter groups that match the pattern
	for _, sign in ipairs(signs[1].signs) do
		if sign.group:match(pattern) then
			table.insert(p4signs, sign)
		end
	end

	if next(p4signs) == nil then
        print("No changes found")
		return
	end

	-- Get the current cursor line
	local current_line = vim.fn.line(".")
	-- Iterate over the signs to find the next one
	local continuous_counter = 1
	helpers._ReverseArray(p4signs)
	for _, sign in ipairs(p4signs) do
		if sign.lnum < current_line then
			if sign.lnum == (current_line - continuous_counter) then
				continuous_counter = continuous_counter + 1
			else
				vim.fn.sign_jump(sign.id, sign.group, buf)
				return
			end
		end
	end
	-- wrap around
	print("Wrap around");
	vim.fn.sign_jump(p4signs[1].id, p4signs[1].group, buf)
end

function M.GoToNextChange()
	local buf = vim.fn.bufnr()
	local p4signs = {}
	local pattern = "^p4signs/.*"

	-- Get all sign groups
	local signs = vim.fn.sign_getplaced(buf, { group = '*' })

	-- Filter groups that match the pattern
	for _, sign in ipairs(signs[1].signs) do
		if sign.group:match(pattern) then
			table.insert(p4signs, sign)
		end
	end

	if next(p4signs) == nil then
        print("No changes found")
		return
	end

	-- Get the current cursor line
	local current_line = vim.fn.line(".")
	-- Iterate over the signs to find the next one
	local continuous_counter = 1
	for _, sign in ipairs(p4signs) do
		if sign.lnum > current_line then
			if sign.lnum == (current_line + continuous_counter) then
				continuous_counter = continuous_counter + 1
			else
				vim.fn.sign_jump(sign.id, sign.group, buf)
				return
			end
		end
	end
	-- wrap around
	print("Wrap around");
	vim.fn.sign_jump(p4signs[1].id, p4signs[1].group, buf)
end

function M.GetP4Data()
	local results = {}

	-- Get opened files
	local opened_paths = file_helpers._GetP4OpenedPaths()
	if opened_paths == nil then
		print("No p4 opened files (or P4 connection failed)")
		return nil
	end

	local opened_files = {}
    local has_default = false
	for _, file in ipairs(opened_paths) do
		opened_files[file[1]] = {file[2],file[3]}
        if file[3] == "default" then
            has_default = true
        end
	end
	results.files = opened_files

	-- Get changelists
	local handle = io.popen("p4 changelists -s pending -c " .. client_helpers._GetClientName())
	if not handle then
		print("Failed to run p4 changelists command")
		return
	end
	local result = handle:read("*a")
	handle:close()
	local pattern = "Change (%d+) on .- '%s*(.-)%s*'"
	local changelists = {}
    if has_default then
        changelists["default"] = "Default changelist"
    end
	for change_number, description in result:gmatch(pattern) do
		changelists[change_number] = description
	end
	results.changelists = changelists

	return results
end

return M
