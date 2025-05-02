-- lua/tdd/utils.lua
local M = {}

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
		"    public function test_example(): void",
		"    {",
		"        $this->assertTrue(true);",
		"    }",
		"}",
		"",
	}
	vim.fn.writefile(lines, path)
end

function M.open_in_split(path)
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_win_get_buf(current_win)
	local current_name = vim.api.nvim_buf_get_name(current_buf)
	local absolute_path = vim.fn.fnamemodify(path, ":p")

	if vim.fn.fnamemodify(current_name, ":p") == absolute_path then
		vim.notify("Test is already open in the current window.", vim.log.levels.INFO)
		return
	end

	local wins = vim.api.nvim_tabpage_list_wins(0)
	for _, win in ipairs(wins) do
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)
		if vim.fn.fnamemodify(name, ":p") == absolute_path then
			vim.api.nvim_set_current_win(win)
			return
		end
	end

	if #wins == 2 then
		for _, win in ipairs(wins) do
			if win ~= current_win then
				vim.api.nvim_set_current_win(win)
				vim.cmd("edit " .. vim.fn.fnameescape(path))
				return
			end
		end
	end

	vim.cmd("vsplit " .. vim.fn.fnameescape(path))
end

return M
