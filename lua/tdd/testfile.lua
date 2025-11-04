local M = {}

local composer = require("tdd.composer")

-- ========= helpers =========

local function normalize(path)
	if not path or path == "" then
		return ""
	end
	path = tostring(path):gsub("\\", "/"):gsub("//+", "/")
	path = path:gsub("/%./", "/") -- collapse '/./'
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
	ns = ns or ""
	if ns ~= "" and not ns:match("\\$") then
		ns = ns .. "\\"
	end
	return ns
end

local function ns_trim_trailing(ns)
	ns = ns or ""
	return (ns:gsub("\\+$", ""))
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
			table.insert(np, ensure_trailing_slash(p)) -- keep RELATIVE
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

local function first_segment(ns) -- "JwPlayer\\Entity\\" -> "JwPlayer"
	local seg = (ns or ""):match("^([^\\]+)\\")
	return seg or ""
end

local function suffix_after_vendor(ns) -- "JwPlayer\\Entity\\" -> "Entity\\"
	ns = ns_ensure_trailing(ns or "")
	local vendor = first_segment(ns)
	if vendor == "" then
		return ""
	end
	local after = ns:sub(#vendor + 2)
	return ns_ensure_trailing(after)
end

-- ========= public API =========

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

-- get_test_info(source_path, composer_config [, cfg_or_debug [, debug]])
-- No namespace config needed; everything derived from composer.json.
function M.get_test_info(source_path, composer_config, cfg_or_debug, debug)
	local user_cfg = nil
	local debug_mode = false
	if type(cfg_or_debug) == "table" then
		user_cfg = cfg_or_debug
		debug_mode = (type(debug) == "boolean") and debug or false
	elseif type(cfg_or_debug) == "boolean" then
		debug_mode = cfg_or_debug
	end

	local dbg = {}

	-- 1) root + source_rel
	local full_source_abs = normalize(source_path)
	local root_abs = normalize(composer_config.__root or composer.find_project_root(full_source_abs) or "")
	if root_abs == "" then
		return (debug_mode and nil or nil), (debug_mode and { error = "no_project_root" } or nil)
	end

	local source_rel = relative_path(full_source_abs, root_abs)
	if not source_rel then
		return (debug_mode and nil or nil),
			(debug_mode and { error = "source_not_under_root", root = root_abs, full = full_source_abs } or nil)
	end

	dbg.root = root_abs
	dbg.full_source = full_source_abs
	dbg.source_rel = source_rel

	-- 2) PSR-4 maps (REL)
	local prod_psr4 = psr4_map_to_list(composer_config.autoload and composer_config.autoload["psr-4"] or {})
	local dev_psr4 =
		psr4_map_to_list(composer_config["autoload-dev"] and composer_config["autoload-dev"]["psr-4"] or {})
	dbg.prod_psr4 = prod_psr4
	dbg.dev_psr4 = dev_psr4

	-- 3) choose best prod mapping by REL path
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
		return (debug_mode and nil or nil), (debug_mode and dbg or nil)
	end

	local rel_inside_prod = relative_path(source_rel, chosen_root_rel)
	if not rel_inside_prod then
		return (debug_mode and nil or nil), (debug_mode and dbg or nil)
	end
	dbg.relative_from_prod_root = rel_inside_prod

	-- 4) class info
	local class_rel_no_ext = rel_inside_prod:gsub("%.php$", "")
	local class_ns_suffix = class_rel_no_ext:gsub("/", "\\")
	local class_full_ns = chosen_ns .. class_ns_suffix
	local class_name = basename_no_ext(source_rel)
	dbg.class_full_ns = class_full_ns

	local vendor = first_segment(chosen_ns)
	local vendor_suffix_ns = suffix_after_vendor(chosen_ns) -- e.g. "Entity\\"
	local vendor_suffix_path = normalize(vendor_suffix_ns):gsub("\\", "/") -- e.g. "Entity/"
	local ns_part = (class_ns_suffix:match("^(.*)\\[^\\]+$") or "")

	-- 5) pick dev mapping (REL), no user config
	local selected_dev = nil
	local dev_by_ns = {}
	for _, entry in ipairs(dev_psr4) do
		dev_by_ns[entry.namespace] = entry
	end

	local preferred_ns_A = ns_ensure_trailing(vendor .. "\\Tests") -- "Vendor\\Tests\\"
	local preferred_ns_B = ns_ensure_trailing("Test\\" .. vendor) -- "Test\\Vendor\\"
	if dev_by_ns[preferred_ns_A] then
		selected_dev = dev_by_ns[preferred_ns_A]
	end
	if not selected_dev and dev_by_ns["Tests\\"] then
		selected_dev = dev_by_ns["Tests\\"]
	end
	if not selected_dev then
		local best_len, best_entry = -1, nil
		for _, entry in ipairs(dev_psr4) do
			local entry_ns = entry.namespace
			local suffix_ns = entry_ns
			if suffix_ns:sub(1, #preferred_ns_A) == preferred_ns_A then
				suffix_ns = suffix_ns:sub(#preferred_ns_A + 1)
			elseif suffix_ns:sub(1, #"Tests\\") == "Tests\\" then
				suffix_ns = suffix_ns:sub(#"Tests\\" + 1)
			elseif suffix_ns:sub(1, #preferred_ns_B) == preferred_ns_B then
				suffix_ns = suffix_ns:sub(#preferred_ns_B + 1)
			elseif suffix_ns:sub(1, #"Test\\") == "Test\\" then
				suffix_ns = suffix_ns:sub(#"Test\\" + 1)
			end
			if suffix_ns ~= "" and chosen_ns:sub(-#suffix_ns) == suffix_ns then
				if #suffix_ns > best_len then
					best_len = #suffix_ns
					best_entry = entry
				end
			end
		end
		if best_entry then
			selected_dev = best_entry
		end
	end

	-- 6) build test namespace + root dir (REL)
	local test_namespace
	local test_root_dir_rel

	if selected_dev then
		local dev_ns = selected_dev.namespace
		local dev_root_rel = ensure_trailing_slash(selected_dev.paths[1] or "")
		if dev_ns == preferred_ns_A or dev_ns == "Tests\\" then
			test_namespace = ns_ensure_trailing(dev_ns) .. vendor_suffix_ns .. ns_part
			test_root_dir_rel = ensure_trailing_slash(join_paths(dev_root_rel, vendor_suffix_path))
		else
			test_namespace = ns_ensure_trailing(dev_ns) .. ns_part
			test_root_dir_rel = dev_root_rel
		end
	else
		test_namespace = ns_ensure_trailing("Tests\\") .. chosen_ns .. ns_part
		test_root_dir_rel = ensure_trailing_slash("tests/")
	end

	test_namespace = ns_trim_trailing(test_namespace)
	dbg.test_namespace = test_namespace
	dbg.test_root_dir_rel = test_root_dir_rel

	-- 7) build REL test path, handle top-level dirname="."
	local class_dir_rel_raw = dirname(rel_inside_prod)
	local class_dir_rel = (class_dir_rel_raw == "." or class_dir_rel_raw == "") and "" or class_dir_rel_raw
	local test_dir_rel = (class_dir_rel ~= "" and join_paths(test_root_dir_rel, class_dir_rel))
		or normalize(test_root_dir_rel)
	local pattern = "%sTest.php"
	if user_cfg and type(user_cfg.test_filename_pattern) == "string" and user_cfg.test_filename_pattern ~= "" then
		pattern = user_cfg.test_filename_pattern
	end
	local test_filename = string.format(pattern, class_name)
	local test_path_rel = join_paths(test_dir_rel, test_filename)
	local test_path_abs = join_paths(root_abs, test_path_rel)

	dbg.test_path_rel = test_path_rel
	dbg.test_path_abs = test_path_abs

	local result = {
		path = test_path_abs,
		namespace = test_namespace,
		class_name = class_name .. "Test",
	}

	if debug_mode then
		return result, dbg
	end
	return result
end

return M
