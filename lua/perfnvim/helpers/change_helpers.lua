local M = {}

function M._GetP4FileRevision(file_path, buf_id)
  -- Get the original file content from P4
  local revision_output = {}

  local function on_stdout(job_id, data, event)
    if event == "stdout" and data then
      for _, line in ipairs(data) do
        line = string.gsub(line, '\r$', '')
        table.insert(revision_output, line)
      end
    end
  end

  local function on_exit(job_id, exit_code, event)
    if event == "exit" then
      table.remove(revision_output, 1)

      require("mini.diff").set_ref_text(buf_id, revision_output)
    end
  end

  vim.fn.jobstart("p4 print " .. file_path .. "#have", {
    on_stdout = on_stdout,
    on_exit = on_exit,
    stdout_buffered = true,
  })
end

return M
