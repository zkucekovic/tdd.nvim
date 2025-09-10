local M = {}

local composer = require("tdd.composer")
local testfile = require("tdd.testfile")
local utils = require("tdd.utils")

-- Defaults (can be overridden via setup(opts))
M.config = {
	-- Namespace root for tests (typical choices: "Tests\\" or "Test\\")
	test_namespace_root = "Tests\\",
	-- Directory (relative to project root) where tests live when autoload-dev mapping is absent
	test_dir = "tests/",
	-- How to open the target test: "reuse" | "vsplit" | "split" | "current"
	open_strategy = "vsplit",
	-- Filename pattern for tests; %s will be replaced with class name
	test_filename_pattern = "%sTest.php",
	-- Whether to try jumping/creating a method for symbol under cursor (not implemented here)
	method_from_cursor = false,
}

local function apply_user_config(opts)
	if type(opts) == "table" then
		M.config = vim.tbl_deep_extend("force", M.config, opts)
	end
end

function M.setup(opts)
	apply_user_config(opts)

	vim.api.nvim_create_user_command("GetTest", function()
		M.open_or_create_test()
	end, {})

	vim.api.nvim_create_user_command("GetTestDebug", function()
		local filepath = vim.api.nvim_buf_get_name(0)
		local root = composer.find_project_root(filepath)
		if not root then
			vim.notify("composer.json not found.", vim.log.levels.ERROR)
			return
		end
		local cfg = composer.load_config(root)
		if not cfg then
			vim.notify("Failed to parse composer.json.", vim.log.levels.ERROR)
			return
		end
		local info, dbg = testfile.get_test_info(filepath, cfg, M.config, true)
		utils.echo_table({ info = info, debug = dbg })
	end, {})
end

function M.open_or_create_test()
	local filepath = vim.api.nvim_buf_get_name(0)
	if testfile.is_test_file(filepath) then
		vim.notify("You are already in a test file.", vim.log.levels.INFO)
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

	local result = testfile.get_test_info(filepath, config, M.config)
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
				utils.open_with_strategy(test_path, M.config.open_strategy)
			elseif choice == nil then
				vim.notify("Cancelled.", vim.log.levels.INFO)
			end
		end)
	else
		vim.ui.select({ "Yes", "No" }, { prompt = "Test file not found. Create it?" }, function(choice)
			if choice == "Yes" then
				utils.ensure_dir(test_path)
				utils.write_phpunit_stub(test_path, test_namespace, class_name)
				utils.open_with_strategy(test_path, M.config.open_strategy)
			elseif choice == nil then
				vim.notify("Cancelled.", vim.log.levels.INFO)
			end
		end)
	end
end

return M
