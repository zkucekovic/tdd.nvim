local M = {}

function M.get_test_info(source_path, composer_config)
	local autoload = composer_config.autoload and composer_config.autoload["psr-4"] or {}
	local devload = composer_config["autoload-dev"] and composer_config["autoload-dev"]["psr-4"] or {}

	for ns, src in pairs(autoload) do
		src = src:gsub("/$", "")
		local dev_ns = "Test\\" .. ns
		local test_src = devload[dev_ns]
		if test_src and source_path:find(src, 1, true) then
			local relative = source_path:sub(#src + 2)
			local test_path = test_src .. "/" .. relative:gsub("%.php$", "Test.php")
			local class_part = relative:gsub("/", "\\"):gsub("%.php$", "Test")
			return {
				path = vim.fn.fnamemodify(test_path, ":p"),
				namespace = dev_ns .. class_part:match("^(.*)\\[^\\]+$"),
				class_name = class_part:match("([^\\]+)$"),
			}
		end
	end

	return nil
end

return M
