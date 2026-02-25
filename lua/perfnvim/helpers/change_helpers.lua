local M = {}

function M._GetP4FileRevision(file_path, callback)
	-- Get the original file content from P4
	local revision_output = {}

	local function on_stdout(job_id, data, event)
		if event == "stdout" and data then
			for _, line in ipairs(data) do
				table.insert(revision_output, line)
			end
		end
	end

	local function on_exit(job_id, exit_code, event)
		if event == "exit" then
			-- Filter out the P4 header line (first line is metadata)
			-- P4 print output starts with: //depot/path#revision - line count
			table.remove(revision_output, 1)
			callback(revision_output)
		end
	end

	vim.fn.jobstart("p4 print " .. file_path .. "#have", {
		on_stdout = on_stdout,
		on_exit = on_exit,
		stdout_buffered = true,
	})
end

return M
