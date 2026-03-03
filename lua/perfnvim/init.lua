local commands = require("perfnvim.commands")
local json = require ("perfnvim.json")
local client_helpers = require("perfnvim.helpers.client_helpers")
local change_helpers = require("perfnvim.helpers.change_helpers")

local M = {}
M.opts = {}

local update_global_values_cb = vim.uv.new_async(function(changelists, opened_files)
    vim.g.perfnvim_thread_running = false

    vim.g.perfnvim_p4_changelists = json.decode(changelists)
    local files = json.decode(opened_files)

    -- Transform files to be relative to client_root
    local opened_files_info = {}
    for file, file_info in pairs(files) do
        local type = file_info[1]
        local chlist = file_info[2]
        local relative_path = file:gsub("^" .. vim.g.perfnvim_client_root .. "/", "")
        table.insert(opened_files_info, { full_path = file, relative_path = relative_path, changelist = chlist, type = type})
    end
    -- save relative_files to a global variable
    vim.g.perfnvim_p4_opened_files = opened_files_info

end)

local function perfnvim_timer_callback()
    if vim.g.perfnvim_enable == false or vim.g.perfnvim_thread_running == true then
        return
    end
    if(vim.g.perfnvim_thread_running == false ) then
        vim.g.perfnvim_thread_running = true
        vim.uv.new_thread({}, function(cb)
            local cmds = require("perfnvim.commands")
            local json = require("perfnvim.json")
            local results = cmds.GetP4Data()
            if results == nil then
                print("Cant connect to P4")
                vim.uv.async_send(cb, json.encode({}), json.encode({}))
                return
            end
            local serialized_changelists = json.encode(results.changelists)
            local serialized_files = json.encode(results.files)

            vim.uv.async_send(cb, serialized_changelists, serialized_files)
        end, update_global_values_cb)
    end
end

function M.setup(opts)
    M.timer = 5000;
    M.opts = opts or {}
	vim.api.nvim_create_user_command("P4add", function()
		commands.SelectChangelistInteractively("add")
	end, {})
	vim.api.nvim_create_user_command("P4edit", function()
		commands.SelectChangelistInteractively("edit")
	end, {})
	vim.api.nvim_create_user_command("P4opened", function()
		commands.GetP4Opened()
	end, {})
	vim.api.nvim_create_user_command("P4next", function()
		commands.GoToNextChange()
	end, {})
	vim.api.nvim_create_user_command("P4prev", function()
		commands.GoToPreviousChange()
	end, {})

  vim.g.perfnvim_enable = false
  vim.g.perfnvim_p4_changelists= {}
  vim.g.perfnvim_p4_opened_files= {}
  vim.g.perfnvim_thread_running = false
	vim.g.perfnvim_client_root = client_helpers._GetClientRoot()
  if vim.g.perfnvim_client_root ~= nil then
    print("Perfnvim client root: " .. vim.g.perfnvim_client_root)
  end
  vim.g.perfnvim_picker_backend = M.opts.picker_backend or "telescope"

  if M.opts.timer ~= nil then
      M.timer = M.opts.timer
  end

	M.perfnvim_timer = vim.uv.new_timer()
    if M.opts.autostart == true then
        print("Autostarting perfnvim...")
        M.P4enable()
    end
end

function M.P4add()
	commands.SelectChangelistInteractively("add")
end

function M.P4edit()
	commands.SelectChangelistInteractively("edit")
end

function M.P4opened()
	commands.GetP4Opened()
end

function M.P4enable()
    vim.g.perfnvim_enable = true

    if M.perfnvim_timer ~= nil then
         perfnvim_timer_callback()
         M.perfnvim_timer:start(0, M.timer, perfnvim_timer_callback)
    else
        print("Perfnvim timer is nil")
    end
end

function M.P4disable()
    M.perfnvim_timer:stop()
    vim.g.perfnvim_enable = false
    vim.g.perfnvim_p4_changelists= {}
    vim.g.perfnvim_p4_opened_files= {}
    vim.g.perfnvim_thread_running = false
end

-- Create a P4 source for mini.diff
function M.gen_source_p4()
  return {
    name = "p4",
    attach = function(buf_id)
      -- Make sure to fail if not in a p4 repo
      local handle = io.popen("p4 opened" .. " 2> /dev/null")
      if not handle then return false end
      -- Initial setup: get the reference text from P4
      local file_path = vim.api.nvim_buf_get_name(buf_id)

      if file_path == "" or not file_path:match("%.") then
        return false
      end

      change_helpers._GetP4FileRevision(file_path, buf_id)

      return true
    end,

    apply_hunks = function(buf_id, hunks)
      -- This would apply the hunks back to P4 (e.g., p4 edit, then write)
      local file_path = vim.api.nvim_buf_get_name(buf_id)

      -- Write the file (which triggers P4 to track changes)
      vim.cmd("write")

      print("Changes written. Run 'p4 submit' to submit changes.")
    end,
  }
end

return M
