local M = {}

local composer = require("tdd.composer") -- only to get project root if __root missing

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

local function ensure_trailing_slash(path)
	path = normalize(path)
	if path ~= "" and not path:match("/$") then
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

local function psr4_map_to_list(map)
	local out = {}
	for ns, paths in pairs(map or {}) do
		local lst = to_list(paths)
		local nns = ns_ensure_trailing(ns)
		local np = {}
		for _, p in ipairs(lst) do
			table.insert(np, ensure_trailing_slash(p)) -- NOTE: keep RELATIVE
		end
		table.insert(out, { namespace = nns, paths = np })
	end
	return out
end

local function longest_path_prefix_match(target_rel, candidates_rel)
	local best, best_len = nil, -1
	for _, p in ipairs(candidates_rel or {}) do
		local prefix = ensure_trailing_slash(p)
		if target_rel:sub(1, #prefix) == prefix then
			if #prefix > best_len then
				best, best_len = prefix, #prefix
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

local function relative_path(full, root_prefix)
	full = normalize(full)
	root_prefix = ensure_trailing_slash(root_prefix)
	if full:sub(1, #root_prefix) ~= root_prefix then
		return nil
	end
	return full:sub(#root_prefix + 1)
end

-- broader test detection
function M.is_test_file(filepath)
	if not filepath or filepath == "" then
		return false
	end
	local name = vim.fn.fnamemodify(filepath, ":t")
	if name:match("Test%.php$") then
		return true
	end
	if name:match("Tests%.php$") then
		return true
	end
	if name:lower():match("_test%.php$") then
		return true
	end
	return false
end

-- (source_path, composer_config [, user_cfg [, debug]])
function M.get_test_info(source_path, composer_config, user_cfg, debug)
	user_cfg = user_cfg or {}
	local dbg = {}

	local full_source_abs = normalize(source_path)
	local root_abs = normalize(composer_config.__root or composer.find_project_root(full_source_abs) or "")
	if root_abs == "" then
		return (debug and nil or nil), (debug and { error = "no_project_root" } or nil)
	end

	-- make the source path RELATIVE to project root once
	local source_rel = relative_path(full_source_abs, root_abs)
	if not source_rel then
		return (debug and nil or nil),
			(debug and { error = "source_not_under_root", root = root_abs, full = full_source_abs } or nil)
	end

	dbg.root = root_abs
	dbg.full_source = full_source_abs
	dbg.source_rel = source_rel

	-- Parse RELATIVE psr-4 maps (kept RELATIVE)
	local prod_psr4 = psr4_map_to_list(composer_config.autoload and composer_config.autoload["psr-4"] or {})
	local dev_psr4 =
		psr4_map_to_list(composer_config["autoload-dev"] and composer_config["autoload-dev"]["psr-4"] or {})
	dbg.prod_psr4 = prod_psr4
	dbg.dev_psr4 = dev_psr4

	-- Choose best PROD mapping by matching RELATIVE source against RELATIVE psr-4 paths
	local chosen_ns, chosen_root_rel = nil, nil
	for _, entry in ipairs(prod_psr4) do
		local match_root_rel = longest_path_prefix_match(source_rel, entry.paths)
		if match_root_rel then
			if not chosen_root_rel or #match_root_rel > #chosen_root_rel then
				chosen_root_rel = match_root_rel
				chosen_ns = entry.namespace
			end
		end
	end

	dbg.chosen_prod_ns = chosen_ns
	dbg.chosen_prod_root_rel = chosen_root_rel

	if not chosen_ns or not chosen_root_rel then
		return (debug and nil or nil), (debug and dbg or nil)
	end

	local rel_inside_prod = relative_path(source_rel, chosen_root_rel)
	if not rel_inside_prod then
		return (debug and nil or nil), (debug and dbg or nil)
	end
	dbg.relative_from_prod_root = rel_inside_prod

	-- Compute class info
	local class_rel_no_ext = rel_inside_prod:gsub("%.php$", "")
	local class_ns_suffix = class_rel_no_ext:gsub("/", "\\")
	local class_full_ns = chosen_ns .. class_ns_suffix -- FYI
	local class_name = basename_no_ext(source_rel)

	-- Test root configuration
	local test_ns_root = ns_ensure_trailing(user_cfg.test_namespace_root or "Tests\\")
	local fallback_test_dir = ensure_trailing_slash(user_cfg.test_dir or "tests/")

	-- Pick DEV mapping (RELATIVE). Strategy:
	-- 1) Prefix: target_ns = test_ns_root .. chosen_ns ; take longest dev entry that's a prefix of target_ns
	-- 2) Suffix: if none, strip test_ns_root from dev ns and see if chosen_ns endsWith(dev_suffix)
	local selected_dev_ns, selected_dev_root_rel = nil, nil
	do
		local target_ns = test_ns_root .. chosen_ns
		-- 1) prefix
		for _, entry in ipairs(dev_psr4) do
			local entry_ns = entry.namespace
			if target_ns:sub(1, #entry_ns) == entry_ns then
				if not selected_dev_ns or #entry_ns > #selected_dev_ns then
					selected_dev_ns = entry_ns
					selected_dev_root_rel = entry.paths[1] -- usually one path
				end
			end
		end
		-- 2) suffix (e.g. dev "Tests\\Entity\\" maps prod "JwPlayer\\Entity\\")
		if not selected_dev_ns then
			for _, entry in ipairs(dev_psr4) do
				local entry_ns = entry.namespace
				local dev_suffix = entry_ns
				if dev_suffix:sub(1, #test_ns_root) == test_ns_root then
					dev_suffix = dev_suffix:sub(#test_ns_root + 1) -- e.g. "Entity\"
				end
				if dev_suffix ~= "" and chosen_ns:sub(-#dev_suffix) == dev_suffix then
					if not selected_dev_ns or #dev_suffix > #(selected_dev_ns:sub(#test_ns_root + 1)) then
						selected_dev_ns = entry_ns
						selected_dev_root_rel = entry.paths[1]
					end
				end
			end
		end
	end

	dbg.selected_dev_ns = selected_dev_ns
	dbg.selected_dev_root_rel = selected_dev_root_rel

	local ns_part = (class_ns_suffix:match("^(.*)\\[^\\]+$") or "")

	local test_namespace
	local test_root_dir_rel
	if selected_dev_ns and selected_dev_root_rel then
		test_namespace = selected_dev_ns .. ns_part
		test_root_dir_rel = ensure_trailing_slash(selected_dev_root_rel) -- RELATIVE
	else
		test_namespace = test_ns_root .. chosen_ns .. ns_part
		test_root_dir_rel = ensure_trailing_slash(fallback_test_dir) -- RELATIVE
	end

	dbg.test_namespace = test_namespace
	dbg.test_root_dir_rel = test_root_dir_rel

	-- Build TEST PATH (RELATIVE), then join with root once for filesystem ops
	local class_dir_rel = dirname(rel_inside_prod)
	local test_dir_rel = join_paths(test_root_dir_rel, class_dir_rel)
	local test_filename = string.format(user_cfg.test_filename_pattern or "%sTest.php", class_name)
	local test_path_rel = join_paths(test_dir_rel, test_filename)
	local test_path_abs = join_paths(root_abs, test_path_rel)

	dbg.test_path_rel = test_path_rel
	dbg.test_path_abs = test_path_abs
	dbg.class_full_ns = class_full_ns

	local result = {
		path = test_path_abs, -- absolute only at the very end to open/create
		namespace = test_namespace,
		class_name = class_name .. "Test",
	}

	if debug then
		return result, dbg
	end
	return result
end

return M
