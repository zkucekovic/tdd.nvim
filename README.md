# tdd.nvim

`tdd.nvim` is a Neovim plugin designed to streamline test-driven development for PHP projects. It allows you to quickly jump between a PHP class and its corresponding PHPUnit test, and will create the test file if it doesn't exist. It reads **PSR-4 mappings directly from your project’s `composer.json`** (`autoload` and `autoload-dev`) — **no manual namespace configuration**.

> **NOTE:** This plugin is under active development. Mapping should now be robust (supports PSR-4 arrays, non-`src/` roots, and common test namespace layouts).

## Features

- Detects matching test files based on **PSR-4** mappings in `composer.json`
- Prompts to open an existing test in a vertical split
- Creates a new **PHPUnit test class template** with the correct **namespace and path**
- Parses both **`autoload`** and **`autoload-dev`** sections from `composer.json`
- Automatically finds the **project root**
- **Supports multiple PSR-4 paths** and common test layouts:
  - `YourRootNamespace\Tests\ => tests/` (recommended mirror-after-vendor style)
  - `Tests\ => tests/` (global tests root)
  - Module maps like `Tests\Entity\ => tests/Entity/`
- **Debug command** to inspect how the path/namespace was derived: `:GetTestDebug`

## Installation

Using **Lazy.nvim**:

```lua
{
  "zkucekovic/tdd.nvim",
  config = function()
    require("tdd").setup() -- no config needed
  end,
}
```

*(Optional: track a branch instead of tags)*
```lua
{
  "zkucekovic/tdd.nvim",
  branch = "feature/some-dev-branch",
  version = false,
  config = function()
    require("tdd").setup()
  end,
}
```

## Usage

Open a PHP class from sources folder and run:

```
:GetTest
```

- If a matching test file exists, the plugin will prompt you to open it in a vertical split.
- If it doesn't exist, it will offer to create one using a PHPUnit skeleton. The plugin uses the **PSR-4 autoload mappings** in your `composer.json` to determine the correct file path and namespace, and creates any missing directories.

**Inspect mappings (optional):**
```
:GetTestDebug
```
Open `:messages` to see the chosen PSR-4 roots, computed namespace, and final test path.

> Tip: after changing `composer.json`, run `composer dump-autoload -o`.

## Example (typical PSR-4 library layout)

```
**composer.json**
    {
      "autoload": {
        "psr-4": {
          "MyProject\\Entity\\": "src/Entity/"
        }
      },
      "autoload-dev": {
        "psr-4": {
          "MyProject\\Tests\\": "tests/"
        }
      }
    }
```

**Source file**
```
    src/Entity/Media/Image/EmptyImage.php
```

**Resulting test file**
```
    tests/Entity/Media/Image/EmptyImageTest.php
```

**Resulting test namespace**
```
    <?php
    namespace MyProject\Tests\Entity\Media\Image;
```

## Contributing

Contributions are welcome. Please keep the code simple, modular, and testable. The plugin is in early development, so unit tests are not mandatory yet, but writing clean and reusable modules is encouraged.
