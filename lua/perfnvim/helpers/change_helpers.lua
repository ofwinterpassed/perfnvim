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

local function _ParseP4Diff(diff_output)
	local hunks = {}

	for _, line in ipairs(diff_output) do
		if line:match("^%d+a") then
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

	return hunks
end

function M._AnnotateSigns()
	local file_path = vim.fn.expand("%:p")
	local bufnr = vim.fn.bufnr(file_path, false)

	if bufnr == -1 then
		return
	end

	local diff_output = {}
	local is_opened_for_add = false

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
			local hunks = {}
			
			if is_opened_for_add then
				-- For new files, mark all lines as added
				local line_count = vim.api.nvim_buf_line_count(bufnr)
				hunks = { { type = "add", start = 1, count = line_count } }
			else
				hunks = _ParseP4Diff(diff_output)
			end

			-- Store hunks in buffer variable for mini.diff to use
			vim.api.nvim_buf_set_var(bufnr, "perfnvim_p4_hunks", hunks)

			-- Now enable mini.diff with P4 as the source
			local mini_diff = require("mini.diff")
			mini_diff.enable(bufnr, {
				source = {
					hunks = function(buf)
						local ok, hunks_data = pcall(vim.api.nvim_buf_get_var, buf, "perfnvim_p4_hunks")
						return ok and hunks_data or {}
					end,
				},
			})
		end
	end

	vim.fn.jobstart("p4 diff " .. file_path, {
		on_stdout = on_stdout,
		on_stderr = on_stderr,
		on_exit = on_exit,
		stdout_buffered = true,
	})
end

return M
