local constants = require("perfnvim.constants")

local M = {}

local function _PlaceSigns(signgroupidentifier, signname, lines, file_path)
	for _, line_num in ipairs(lines) do
		vim.fn.sign_place(0, signgroupidentifier, signname, vim.fn.bufnr(file_path), { lnum = line_num })
	end
end

local function _ClearSignsAndPlace(signgroupidentifier, signname, lines, file_path)
	-- Clear existing signs from the buffer
	vim.fn.sign_unplace(signgroupidentifier, { buffer = vim.fn.bufnr(file_path) })
	-- Place new signs
	_PlaceSigns(signgroupidentifier, signname, lines, file_path)
end

function M._AnnotateAddedLines(lines, file_path)
	local added_lines = {}
	for _, line in ipairs(lines) do
		if line:match("^(%d+)a") then
			local start_num, end_num = line:match("%d+a(%d+),(%d+)")
			if start_num and end_num then
				start_num = tonumber(start_num)
				end_num = tonumber(end_num)
				for i = start_num, end_num do
					table.insert(added_lines, i)
				end
			else
				local num = line:match("%d+a(%d+)")
				if num then
					num = tonumber(num)
					table.insert(added_lines, num)
				end
			end
		end
	end
	_ClearSignsAndPlace(constants.p4addSignGroupIdentifier, constants.p4addSignName, added_lines, file_path)
end

function M._AnnotateDeletedLines(lines, file_path)
	local deleted_lines = {}
	for _, line in ipairs(lines) do
		if line:match("^%d+[,?%d+]*d%d+[,?%d+]*") then
			local start_num = line:match("d(%d+)")
			if start_num then
				start_num = tonumber(start_num)
				table.insert(deleted_lines, start_num)
			end
		end
	end
	_ClearSignsAndPlace(constants.p4deletesSignGroupIdentifier, constants.p4deleteSignName, deleted_lines, file_path)
end

function M._AnnotateChangedLines(lines, file_path)
	local changed_lines = {}
	for _, line in ipairs(lines) do
		if line:match("^%d+[,?%d+]*c%d+[,?%d+]*") then
			local start_num, end_num = line:match("c(%d+),?(%d*)")
			if start_num then
				start_num = tonumber(start_num)
				if end_num == "" or end_num == nil then
					end_num = start_num
				else
					end_num = tonumber(end_num)
				end
				for i = start_num, end_num do
					table.insert(changed_lines, i)
				end
			end
		end
	end
	_ClearSignsAndPlace(constants.p4changesSignGroupIdentifier, constants.p4changeSignName, changed_lines, file_path)
end

local function _GetP4DiffSource(file_path)
	return function()
		local diff_output = {}
		local is_opened_for_add = false
		local done = false
		local result = nil

		local function on_stdout(job_id, data, event)
			if event == "stdout" and data then
				for _, line in ipairs(data) do
					table.insert(diff_output, line)
				end
			end
		end

		local function on_stderr(job_id, data, event)
			if event == "stderr" and data then
				for _, line in ipairs(data) do
					if line:match("not opened for edit.") then
						is_opened_for_add = true
					end
				end
			end
		end

		local function on_exit(job_id, exit_code, event)
			if event == "exit" then
				if is_opened_for_add then
					-- For new files, all lines are added
					result = { source = "p4", hunks = { { type = "add", start = 1, count = vim.fn.line("$") } } }
				else
					-- Parse P4 diff output into hunks
					result = _ParseP4Diff(diff_output)
				end
				done = true
			end
		end

		vim.fn.jobstart("p4 diff " .. file_path, {
			on_stdout = on_stdout,
			on_stderr = on_stderr,
			on_exit = on_exit,
			stdout_buffered = true,
		})

		-- Wait for the job to complete
		vim.wait(5000, function() return done end)

		return result
	end
end

local function _ParseP4Diff(diff_output)
	-- Parse P4 diff format (e.g., "1,5c1,4", "1a2,3", "1,2d1")
	-- into hunks that mini.diff understands
	local hunks = {}

	for _, line in ipairs(diff_output) do
		if line:match("^%d+a") then
			-- Addition: "1a2,3" means after line 1, add lines 2-3
			local start_num, end_num = line:match("(%d+)a(%d+),(%d+)")
			if start_num and end_num then
				table.insert(hunks, {
					type = "add",
					start = tonumber(start_num) + 1,
					count = tonumber(end_num) - tonumber(start_num) + 1,
				})
			else
				local num = line:match("(%d+)a(%d+)")
				if num then
					table.insert(hunks, {
						type = "add",
						start = tonumber(num) + 1,
						count = 1,
					})
				end
			end
		elseif line:match("^%d+[,?%d+]*d%d+") then
			-- Deletion: "1,2d1" means delete lines 1-2
			local start_num, end_num = line:match("(%d+),?(%d*)d")
			if start_num then
				if end_num == "" or end_num == nil then
					end_num = start_num
				end
				table.insert(hunks, {
					type = "delete",
					start = tonumber(start_num),
					count = tonumber(end_num) - tonumber(start_num) + 1,
				})
			end
		elseif line:match("^%d+[,?%d+]*c%d+") then
			-- Change: "1,5c1,4" means lines 1-5 changed to 1-4
			local start_num, end_num = line:match("(%d+),?(%d*)c")
			if start_num then
				if end_num == "" or end_num == nil then
					end_num = start_num
				end
				table.insert(hunks, {
					type = "change",
					start = tonumber(start_num),
					count = tonumber(end_num) - tonumber(start_num) + 1,
				})
			end
		end
	end

	return { source = "p4", hunks = hunks }
end

function M._AnnotateSigns()
	local file_path = vim.fn.expand("%:p")
	local bufnr = vim.fn.bufnr(file_path, false)

	if bufnr == -1 then
		return
	end

	-- Enable mini.diff with the P4 source
	require("mini.diff").enable(bufnr, {
		source = _GetP4DiffSource(file_path),
	})
end

return M
