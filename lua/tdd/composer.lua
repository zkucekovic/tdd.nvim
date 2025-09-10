local M = {}

local json = vim.json
local _cache = {}

local function normalize(path)
	if not path or path == "" then
		return ""
	end
	path = tostring(path):gsub("\\", "/"):gsub("//+", "/")
	if #path > 1 then
		path = path:gsub("/+$", "")
	end
	return path
end

local function is_root(dir)
	if dir == "/" then
		return true
	end
	if dir:match("^%a:/$") then
		return true
	end -- Windows drive root
	return false
end

function M.find_project_root(start_path)
	local dir = vim.fn.fnamemodify(start_path, ":p")
	dir = normalize(vim.fn.fnamemodify(dir, ":h"))
	while dir and dir ~= "" do
		if vim.fn.filereadable(dir .. "/composer.json") == 1 then
			return dir
		end
		if is_root(dir) then
			break
		end
		dir = normalize(vim.fn.fnamemodify(dir, ":h"))
	end
	return nil
end

function M.load_config(root)
	root = normalize(root or "")
	if root == "" then
		return nil
	end
	if _cache[root] then
		return _cache[root]
	end

	local file = root .. "/composer.json"
	local ok_read, lines = pcall(vim.fn.readfile, file)
	if not ok_read then
		vim.notify("Failed to read composer.json: " .. tostring(lines), vim.log.levels.ERROR)
		return nil
	end
	local ok, data = pcall(json.decode, table.concat(lines, "\n"))
	if not ok then
		vim.notify("Failed to parse composer.json: " .. tostring(data), vim.log.levels.ERROR)
		return nil
	end
	data.__root = root
	_cache[root] = data
	return data
end

return M
