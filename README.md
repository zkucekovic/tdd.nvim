# tdd.nvim

`tdd.nvim` is a Neovim plugin designed to streamline test-driven development for PHP projects. It allows you to quickly jump between a PHP class and its corresponding PHPUnit test, and will create the test file if it doesn't exist.
NOTE: This plugin is still under development. In future versions, it is expected to handle namespaces and file paths more robustly.

## Features

- Detects matching test files based on PSR-4 mappings in `composer.json`
- Prompts to open an existing test in a vertical split
- Creates a new PHPUnit test class with the correct namespace and path
- Parses both `autoload` and `autoload-dev` sections from `composer.json`
- Automatically finds the project root

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "zkucekovic/tdd.nvim",
  config = function()
    require("tdd").setup()
  end,
}
```

## Usage

Open any PHP class file and run the following command:

```vim
:GetTest
```

If a matching test file exists, the plugin will prompt you to open it in a vertical split. If it doesn't exist, it will offer to create one using a PHPUnit skeleton. The plugin uses the PSR-4 autoload mappings in your `composer.json` file to determine the correct file path and namespace.

## Example

Given a source file:

```
src/Article/src/Repository/Article.php
```

And the following `composer.json` mapping:

```json
"autoload": {
  "psr-4": {
    "Content\\Article\\": "src/Article/src"
  }
},
"autoload-dev": {
  "psr-4": {
    "Test\\Content\\Article\\": "src/Article/tests/src"
  }
}
```

`tdd.nvim` will create or open:

```
src/Article/tests/src/Repository/ArticleTest.php
```

With the following namespace:

```php
namespace Test\Content\Article\Repository;
```

## Contributing

Contributions are welcome. Please keep the code simple, modular, and testable. The plugin is in early development, so unit tests are not mandatory yet, but writing clean and reusable modules is encouraged.

To contribute:

1. Fork or clone the repository
2. Work in a feature branch
3. Test locally with your Neovim setup
4. Submit a pull request
