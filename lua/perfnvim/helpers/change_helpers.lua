local M = {}

local function _GetP4FileRevision(file_path, callback)
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
			callback(revision_output)
		end
	end

	vim.fn.jobstart("p4 print " .. file_path .. "#have", {
		on_stdout = on_stdout,
		on_exit = on_exit,
		stdout_buffered = true,
	})
end

-- Create a P4 source for mini.diff
function M.gen_source_p4()
	return {
		name = "p4",
		attach = function(buf_id)
			-- Initial setup: get the reference text from P4
			local file_path = vim.api.nvim_buf_get_name(buf_id)
			
			if file_path == "" or not file_path:match("%.") then
				return false
			end

			_GetP4FileRevision(file_path, function(revision_lines)
				-- Set the reference text (the original file from P4)
				require("mini.diff").set_ref_text(buf_id, table.concat(revision_lines, "\n"))
			end)

			-- Set up autocommand to update reference text on write
			vim.api.nvim_create_autocmd("BufWritePost", {
				buffer = buf_id,
				callback = function()
					_GetP4FileRevision(file_path, function(revision_lines)
						require("mini.diff").set_ref_text(buf_id, table.concat(revision_lines, "\n"))
					end)
				end,
			})

			return true
		end,

		detach = function(buf_id)
			-- Clean up if needed
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

function M._AnnotateSigns()
	local buf_id = vim.api.nvim_get_current_buf()

	-- Enable mini.diff with the P4 source
	require("mini.diff").enable(buf_id, {
		source = M.gen_source_p4(),
	})
end

return M
