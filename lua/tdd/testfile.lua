local M = {}

local function normalize(path)
	return vim.fn.fnamemodify(path, ":p"):gsub("/+$", "")
end

function M.get_test_info(source_path, composer_config)
	local autoload = composer_config.autoload and composer_config.autoload["psr-4"] or {}
	local devload = composer_config["autoload-dev"] and composer_config["autoload-dev"]["psr-4"] or {}

	local full_source = normalize(source_path)

	for ns, src in pairs(autoload) do
		local src_path = normalize(src)
		local test_ns = "Test\\" .. ns
		local test_path_root = devload[test_ns]

		if test_path_root and full_source:find(src_path, 1, true) == 1 then
			local relative = full_source:sub(#src_path + 2) -- remove matched autoload root
			local test_path = normalize(test_path_root) .. "/" .. relative:gsub("%.php$", "Test.php")

			local class_path = relative:gsub("^src/", ""):gsub("/", "\\"):gsub("%.php$", "Test")
			local ns_part = class_path:match("^(.*)\\[^\\]+$") or ""
			local class_name = class_path:match("([^\\]+)$")

			return {
				path = test_path,
				namespace = test_ns .. ns_part,
				class_name = class_name,
			}
		end
	end

	return nil
end

return M
