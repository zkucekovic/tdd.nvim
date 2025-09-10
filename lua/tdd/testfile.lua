local M = {}

local function normalize(path)
	if not path or path == "" then
		return ""
	end
	path = tostring(path)
	path = path:gsub("\\", "/")
	path = path:gsub("//+", "/")
	if #path > 1 then
		path = path:gsub("/+$", "")
	end
	return path
end

local function ensure_trailing_slash(path)
	path = normalize(path)
	if path == "" then
		return ""
	end
	if not path:match("/$") then
		path = path .. "/"
	end
	return path
end

local function ns_ensure_trailing(ns)
	if ns == "" then
		return ""
	end
	if not ns:match("\\$") then
		return ns .. "\\"
	end
	return ns
end

local function to_list(v)
	if v == nil then
		return {}
	end
	if type(v) == "string" then
		return { v }
	end
	if type(v) == "table" then
		return v
	end
	return {}
end

local function psr4_map_to_list(map)
	local out = {}
	for ns, paths in pairs(map or {}) do
		local lst = to_list(paths)
		local nns = ns_ensure_trailing(ns)
		local np = {}
		for _, p in ipairs(lst) do
			table.insert(np, ensure_trailing_slash(p))
		end
		table.insert(out, { namespace = nns, paths = np })
	end
	return out
end

local function longest_path_prefix_match(fullpath, candidates)
	local best = nil
	local best_len = -1
	for _, p in ipairs(candidates) do
		local prefix = ensure_trailing_slash(normalize(p))
		if fullpath:sub(1, #prefix) == prefix then
			if #prefix > best_len then
				best = prefix
				best_len = #prefix
			end
		end
	end
	return best
end

local function dirname(path)
	return normalize(vim.fn.fnamemodify(path, ":h"))
end

local function basename_no_ext(path)
	local name = vim.fn.fnamemodify(path, ":t")
	return name:gsub("%.php$", "")
end

local function split_ns(ns)
	local parts = {}
	for part in ns:gmatch("([^\\]+)\\") do
		table.insert(parts, part)
	end
	return parts
end

local function join_paths(a, b)
	a = normalize(a)
	b = normalize(b)
	if a == "" then
		return b
	end
	if b == "" then
		return a
	end
	return a .. "/" .. b
end

local function relative_path(full, root)
	full = normalize(full)
	root = ensure_trailing_slash(root)
	if full:sub(1, #root) ~= root then
		return nil
	end
	return full:sub(#root + 1)
end

-- Determine if a file looks like a test file
function M.is_test_file(filepath)
	if not filepath or filepath == "" then
		return false
	end
	local name = vim.fn.fnamemodify(filepath, ":t")
	if name:match("Test%.php$") then
		return true
	end -- FooTest.php
	if name:match("Tests%.php$") then
		return true
	end -- FooTests.php
	if name:lower():match("_test%.php$") then
		return true
	end -- foo_test.php
	return false
end

-- Core: map a source file to a test file/namespace/class
-- If debug is true, returns (result, debug_table)
function M.get_test_info(source_path, composer_config, user_cfg, debug)
	user_cfg = user_cfg or {}
	local dbg = {}
	local full_source = normalize(source_path)
	local root = normalize(composer_config.__root or "")
	dbg.root = root
	dbg.full_source = full_source

	local prod_psr4 = psr4_map_to_list(composer_config.autoload and composer_config.autoload["psr-4"] or {})
	local dev_psr4 =
		psr4_map_to_list(composer_config["autoload-dev"] and composer_config["autoload-dev"]["psr-4"] or {})

	dbg.prod_psr4 = prod_psr4
	dbg.dev_psr4 = dev_psr4

	-- Find best matching prod mapping (namespace + path)
	local chosen_ns = nil
	local chosen_root = nil

	for _, entry in ipairs(prod_psr4) do
		local match_root = longest_path_prefix_match(full_source, entry.paths)
		if match_root then
			if not chosen_root or #match_root > #chosen_root then
				chosen_root = match_root
				chosen_ns = entry.namespace
			end
		end
	end

	dbg.chosen_prod_ns = chosen_ns
	dbg.chosen_prod_root = chosen_root

	if not chosen_ns or not chosen_root then
		return debug and nil or nil, debug and dbg or nil
	end

	local rel = relative_path(full_source, chosen_root)
	if not rel then
		return debug and nil or nil, debug and dbg or nil
	end
	dbg.relative_from_prod_root = rel

	-- Compute class-related info
	local class_rel_no_ext = rel:gsub("%.php$", "")
	local class_ns_suffix = class_rel_no_ext:gsub("/", "\\")
	local class_full_ns = chosen_ns .. class_ns_suffix
	local class_name = basename_no_ext(full_source)

	-- Compute test namespace root and test dir
	local test_ns_root = ns_ensure_trailing(user_cfg.test_namespace_root or "Tests\\")
	local fallback_test_dir = ensure_trailing_slash(user_cfg.test_dir or "tests/")

	-- Try to find a matching dev mapping (prefer exact test_ns_root, otherwise the longest prefix)
	local selected_dev_ns = nil
	local selected_dev_root = nil
	for _, entry in ipairs(dev_psr4) do
		for _, p in ipairs(entry.paths) do
			-- pick the mapping whose namespace is the longest prefix of test_ns_root .. chosen_ns
			local target_ns = test_ns_root .. chosen_ns
			local entry_ns = entry.namespace
			if target_ns:sub(1, #entry_ns) == entry_ns then
				if not selected_dev_ns or #entry_ns > #selected_dev_ns then
					selected_dev_ns = entry_ns
					selected_dev_root = p
				end
			end
		end
	end

	dbg.selected_dev_ns = selected_dev_ns
	dbg.selected_dev_root = selected_dev_root

	local ns_part = ""
	do
		local tmp = class_ns_suffix:match("^(.*)\\[^\\]+$") or ""
		ns_part = tmp
	end

	local test_namespace
	local test_root_dir

	if selected_dev_ns and selected_dev_root then
		-- Build namespace by replacing chosen_ns with selected_dev_ns at the front
		-- Example: chosen_ns = "Vendor\\Pkg\\", selected_dev_ns = "Tests\\Vendor\\Pkg\\"
		-- Then test_namespace = selected_dev_ns .. ns_part
		test_namespace = selected_dev_ns .. ns_part
		test_root_dir = selected_dev_root
	else
		-- Fallback: mirror directory tree under configured tests dir, and namespace under test_ns_root + chosen_ns
		test_namespace = test_ns_root .. chosen_ns .. ns_part
		test_root_dir = join_paths(root, fallback_test_dir)
	end

	dbg.test_namespace = test_namespace
	dbg.test_root_dir = test_root_dir

	-- Build test path
	local class_dir_rel = dirname(rel)
	local test_dir_full = join_paths(test_root_dir, class_dir_rel)
	local test_filename = string.format(user_cfg.test_filename_pattern or "%sTest.php", class_name)
	local test_path = join_paths(test_dir_full, test_filename)

	local result = {
		path = normalize(test_path),
		namespace = test_namespace,
		class_name = class_name .. "Test",
	}

	if debug then
		return result, dbg
	end
	return result
end

return M
