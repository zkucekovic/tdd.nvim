local root = vim.fn.getcwd()
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local composer = require("tdd.composer")
local testfile = require("tdd.testfile")

local function assert_equal(actual, expected, context)
	if not vim.deep_equal(actual, expected) then
		error(
			string.format(
				"%s\nexpected: %s\nactual: %s",
				context or "values are not equal",
				vim.inspect(expected),
				vim.inspect(actual)
			)
		)
	end
end

local function assert_true(value, context)
	if not value then
		error(context or "expected value to be truthy")
	end
end

local function assert_false(value, context)
	if value then
		error(context or "expected value to be falsy")
	end
end

local requirements = {}

requirements[#requirements + 1] = {
	description = "Project root detection stops at the first ancestor that carries a composer.json file",
	run = function()
		local tmp = vim.fn.tempname()
		vim.fn.mkdir(tmp .. "/workspace/nested/deep", "p")
		local composer_path = tmp .. "/workspace/composer.json"
		vim.fn.writefile({ [[{"name": "example/project"}]] }, composer_path)

		local start_path = tmp .. "/workspace/nested/deep/file.php"
		local detected = composer.find_project_root(start_path)

		assert_equal(detected, tmp .. "/workspace", "should pick the nearest ancestor with composer.json")
	end,
}

requirements[#requirements + 1] = {
	description = "Composer configuration loading returns parsed JSON once and serves cached table afterwards",
	run = function()
		local tmp = vim.fn.tempname()
		vim.fn.mkdir(tmp .. "/project", "p")
		local composer_path = tmp .. "/project/composer.json"
		vim.fn.writefile({
			'{',
			'  "name": "example/project",',
			'  "autoload": { "psr-4": {"App\\\\": "src/"} }',
			'}',
		}, composer_path)

		local first = composer.load_config(tmp .. "/project")
		assert_equal(first.__root, tmp .. "/project", "loaded config should expose its root path")

		local second = composer.load_config(tmp .. "/project")
		assert_true(first == second, "cached config should return the same table reference")
	end,
}

requirements[#requirements + 1] = {
	description = "Test-file detection recognises canonical test name suffixes and rejects non-test files",
	run = function()
		assert_true(testfile.is_test_file("FeedTest.php"), "should accept *Test.php suffix")
		assert_true(testfile.is_test_file("FeedTests.php"), "should accept *Tests.php suffix")
		assert_true(testfile.is_test_file("feed_test.php"), "should accept *_test.php suffix")
		assert_false(testfile.is_test_file("Feed.php"), "should reject non-test file names")
	end,
}

requirements[#requirements + 1] = {
	description = "Test discovery maps production classes to their vendor-specific autoload-dev namespaces",
	run = function()
		local cfg = {
			__root = "/project",
			autoload = { ["psr-4"] = { ["Vendor\\Module\\"] = { "src/Module/" } } },
			["autoload-dev"] = { ["psr-4"] = {
				["Test\\Vendor\\Module\\"] = { "tests/Module/" },
				["Test\\Vendor\\Shared\\"] = { "tests/Shared/" },
			} },
		}
		local source = "/project/src/Module/Feature/Service.php"

		local info = testfile.get_test_info(source, cfg)

		assert_equal(info.path, "/project/tests/Module/Feature/ServiceTest.php", "should choose matching Test\\Vendor\\ mapping")
		assert_equal(info.namespace, "Test\\Vendor\\Module\\Feature", "dev namespace should combine vendor tests prefix and class namespace")
		assert_equal(info.class_name, "ServiceTest", "test class should mirror production class name with Test suffix")
	end,
}

requirements[#requirements + 1] = {
	description = "Fallback mapping sends tests to the shared tests directory when no dev PSR-4 entry matches",
	run = function()
		local cfg = {
			__root = "/project",
			autoload = { ["psr-4"] = { ["Vendor\\Solo\\"] = { "src/Solo/" } } },
			["autoload-dev"] = { ["psr-4"] = {} },
		}
		local source = "/project/src/Solo/Unit.php"

		local info = testfile.get_test_info(source, cfg)

		assert_equal(info.path, "/project/tests/UnitTest.php", "without autoload-dev match, it should fall back to top-level tests directory")
		assert_equal(info.namespace, "Tests\\Vendor\\Solo", "fallback namespace should be under Tests vendor namespace")
	end,
}

requirements[#requirements + 1] = {
	description = "Custom filename patterns are honoured while keeping namespace and directories intact",
	run = function()
		local cfg = {
			__root = "/project",
			autoload = { ["psr-4"] = { ["Vendor\\Feature\\"] = { "lib/Feature/" } } },
			["autoload-dev"] = { ["psr-4"] = { ["Tests\\"] = { "spec/" } } },
		}
		local source = "/project/lib/Feature/Thing.php"
		local info = testfile.get_test_info(source, cfg, { test_filename_pattern = "test_%s.php" })

		assert_equal(info.path, "/project/spec/Feature/test_Thing.php", "should apply custom pattern while keeping directory mapping")
		assert_equal(info.namespace, "Tests\\Feature", "namespace should stay consistent with selected dev namespace")
		assert_equal(info.class_name, "ThingTest", "class naming still appends Test suffix")
	end,
}

local failures = {}
for _, requirement in ipairs(requirements) do
	local ok, err = pcall(requirement.run)
	if not ok then
		failures[#failures + 1] = string.format("- %s:\n  %s", requirement.description, err)
	end
end

if #failures > 0 then
	error("The following requirements are not satisfied:\n" .. table.concat(failures, "\n"))
end

print("All documented requirements are satisfied.")
