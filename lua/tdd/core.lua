local M = {}

local composer = require("tdd.composer")
local testfile = require("tdd.testfile")
local utils = require("tdd.utils")

function M.setup()
	vim.api.nvim_create_user_command("GetTest", function()
		M.open_or_create_test()
	end, {})
end

function M.open_or_create_test()
	local filepath = vim.api.nvim_buf_get_name(0)
	if not filepath:match("%.php$") then
		vim.notify("Not a PHP file.", vim.log.levels.WARN)
		return
	end

	local root = composer.find_project_root(filepath)
	if not root then
		vim.notify("composer.json not found.", vim.log.levels.ERROR)
		return
	end

	local config = composer.load_config(root)
	if not config then
		vim.notify("Failed to parse composer.json.", vim.log.levels.ERROR)
		return
	end

	local result = testfile.get_test_info(filepath, config)
	if not result then
		vim.notify("Could not determine test file path.", vim.log.levels.ERROR)
		return
	end

	local test_path = result.path
	local test_namespace = result.namespace
	local class_name = result.class_name

	if vim.fn.filereadable(test_path) == 1 then
		vim.ui.select({ "Yes", "No" }, { prompt = "Test file found. Open it?" }, function(choice)
			if choice == "Yes" then
				utils.open_in_split(test_path)
			end
		end)
	else
		vim.ui.select({ "Yes", "No" }, { prompt = "Test file not found. Create it?" }, function(choice)
			if choice == "Yes" then
				utils.ensure_dir(test_path)
				utils.write_phpunit_stub(test_path, test_namespace, class_name)
				utils.open_in_split(test_path)
			end
		end)
	end
end

return M
