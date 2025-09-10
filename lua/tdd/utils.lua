-- lua/tdd/utils.lua
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

function M.ensure_dir(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

function M.write_phpunit_stub(path, namespace, class_name)
	local lines = {
		"<?php",
		"",
		"declare(strict_types=1);",
		"",
		"namespace " .. namespace .. ";",
		"",
		"use PHPUnit\\Framework\\TestCase;",
		"",
		"final class " .. class_name .. " extends TestCase",
		"{",
		"    protected function setUp(): void",
		"    {",
		"        parent::setUp();",
		"        // Arrange common fixtures",
		"    }",
		"",
		"    public function test_example(): void",
		"    {",
		"        // Arrange",
		"        // Act",
		"        // Assert",
		"        $this->assertTrue(true);",
		"    }",
		"}",
		"",
	}
	vim.fn.writefile(lines, path)
end

local function path_equal(a, b)
	a = normalize(vim.fn.fnamemodify(a, ":p"))
	b = normalize(vim.fn.fnamemodify(b, ":p"))
	return a == b
end

-- Open using strategy: "reuse" | "vsplit" | "split" | "current"
function M.open_with_strategy(path, strategy)
	strategy = strategy or "vsplit"
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_win_get_buf(current_win)
	local current_name = vim.api.nvim_buf_get_name(current_buf)
	local absolute_path = vim.fn.fnamemodify(path, ":p")

	if path_equal(current_name, absolute_path) then
		vim.notify("Test is already open in the current window.", vim.log.levels.INFO)
		return
	end

	-- Try reuse in current tab
	local wins = vim.api.nvim_tabpage_list_wins(0)
	for _, win in ipairs(wins) do
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)
		if path_equal(name, absolute_path) then
			vim.api.nvim_set_current_win(win)
			return
		end
	end

	if strategy == "current" then
		vim.cmd.edit(vim.fn.fnameescape(path))
		return
	elseif strategy == "split" then
		vim.cmd("split " .. vim.fn.fnameescape(path))
		return
	elseif strategy == "reuse" and #wins == 2 then
		for _, win in ipairs(wins) do
			if win ~= current_win then
				vim.api.nvim_set_current_win(win)
				vim.cmd("edit " .. vim.fn.fnameescape(path))
				return
			end
		end
	end

	-- default: vsplit
	vim.cmd("vsplit " .. vim.fn.fnameescape(path))
end

-- Debug helper: pretty print a table to messages
function M.echo_table(tbl)
	local function serialize(o, indent)
		indent = indent or 0
		local pad = string.rep(" ", indent)
		if type(o) == "table" then
			local s = "{\n"
			for k, v in pairs(o) do
				s = s .. pad .. "  " .. tostring(k) .. " = " .. serialize(v, indent + 2) .. "\n"
			end
			return s .. pad .. "}"
		else
			return tostring(o)
		end
	end
	vim.notify(serialize(tbl), vim.log.levels.INFO)
end

return M
