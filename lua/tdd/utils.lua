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
	local cur_win = vim.api.nvim_get_current_win()
	local tab = vim.api.nvim_get_current_tabpage()
	local wins = vim.api.nvim_tabpage_list_wins(tab)

	for _, win in ipairs(wins) do
		if win ~= cur_win and vim.api.nvim_win_get_height(win) > vim.api.nvim_win_get_width(win) then
			vim.api.nvim_set_current_win(win)
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			return
		end
	end

	vim.cmd("vsplit " .. vim.fn.fnameescape(path))
end

return M
