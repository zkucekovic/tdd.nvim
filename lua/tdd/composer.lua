local M = {}

local json = vim.json

-- simple memoization to avoid repeated reads
local _cache = {}

local function normalize(path)
	if not path or path == "" then
		return ""
	end
	path = tostring(path)
	path = path:gsub("\\", "/")
	-- collapse multiple slashes
	path = path:gsub("//+", "/")
	-- remove trailing slashes (keep root "/")
	if #path > 1 then
		path = path:gsub("/+$", "")
	end
	return path
end

function M.find_project_root(start_path)
	local dir = vim.fn.fnamemodify(start_path, ":p")
	dir = normalize(vim.fn.fnamemodify(dir, ":h"))
	-- On Windows, stop at drive root like "C:/"
	local function is_root(d)
		if d == "/" then
			return true
		end
		if d:match("^%a:/$") then
			return true
		end
		return false
	end
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
