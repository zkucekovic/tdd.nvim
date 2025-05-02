local M = {}

local json = vim.json

function M.find_project_root(start_path)
	local dir = vim.fn.fnamemodify(start_path, ":h")
	while dir and dir ~= "/" do
		if vim.fn.filereadable(dir .. "/composer.json") == 1 then
			return dir
		end
		dir = vim.fn.fnamemodify(dir, ":h")
	end
	return nil
end

function M.load_config(root)
	local file = root .. "/composer.json"
	local lines = vim.fn.readfile(file)
	local ok, data = pcall(json.decode, table.concat(lines, "\n"))
	return ok and data or nil
end

return M
