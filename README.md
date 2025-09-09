# Project Picker

A fast, interactive project launcher for zsh. Supports multiple scopes, fuzzy search, and editor integration.

## Features

- Define scopes for different project roots (work, personal, language, etc.)
- Fuzzy or menu-based project selection (fzf optional)
- Editor and preview integration
- Per-scope and global config via TOML
- Auto-generates commands: `p`, `p<key>`, `p<key>l`, `ppl`, `pwl`, etc.
- Optional dependencies: `fd`, `fzf`, `tree` (falls back to built-ins)
- Works on Linux, macOS, and Windows (with zsh)

## Quick Start

1. Clone the repo and source the plugin in your `.zshrc`:
   ```sh
   source /path/to/project-picker/project-picker.plugin.zsh
   ```
2. Run the config wizard (choose one):
   ```sh
   # Plugin function (recommended):
   p config
   # Or CLI:
   ppicker init
   ```
3. Validate config (choose one):
   ```sh
   p doctor
   # Or CLI:
   ppicker doctor
   ```
4. Pick a project:
   ```sh
   p
   # or for a scope: pw, pp, etc.
   # open last: pwl, ppl
   ```

## Commands

- `p config` — run config wizard (plugin)
- `p doctor` — validate config and dependencies (plugin)
- `p reload` — reload plugin functions after config change
- `ppicker init` — run config wizard (CLI)
- `ppicker doctor` — validate config and dependencies (CLI)
- `ppicker reload` — reload config and regenerate plugin functions (CLI)
- `p` — pick a project from any scope
- `p<key>` — pick in a specific scope (e.g. `pw`, `pp`, `py`, `js`)
- `p<key>l` — open last in scope (e.g. `pwl`, `ppl`, `pyl`, `jsl`)

## Configuration

- Config file: `$XDG_CONFIG_HOME/project-picker/config.toml` or `$HOME/.config/project-picker/config.toml`
- Use `p config` or `ppicker init` to set up scopes, editors, excludes, etc.
- `history_max_lines` (in `[global]`) sets the maximum number of lines kept in the history log (default: 1000). If the log exceeds this, it is trimmed to the newest N lines automatically.

### TOML Schema

#### [global] section

```toml
[global]
cache_ttl_min = 10           # Minutes to cache project lists
# Optional global overrides (used if not set per-scope):
# default_editor = "code"
# preview = "tree"
# depth = 1
# excludes = ["node_modules", ".git"]
# include_workspaces = true
# history_max_lines = 1000   # (default, can be set to another value)
```

#### [scopes.<key>] section

Each scope defines a project root, label, editor, and optional overrides:

```toml
[scopes.p]
label = "personal"
paths = ["~/mywork"]
editor = "code"

[scopes.w]
label = "work"
paths = ["~/work"]
editor = "code"

[scopes.py]
label = "python"
paths = ["~/dev/python", "~/src/python"]
editor = "nvim"
depth = 2
excludes = [".venv", "__pycache__"]
include_workspaces = false

[scopes.js]
label = "javascript"
paths = ["~/dev/js", "~/src/js"]
editor = "code"
excludes = ["node_modules", ".git", "dist"]
```

#### Per-scope overrides

- `editor`, `depth`, `excludes`, and `include_workspaces` can be set per-scope.
- If omitted, global values are used.
- `paths` is always required per-scope (array of directories).

### Example: Multi-language, multi-scope config

```toml
[global]
cache_ttl_min = 15
preview = "tree"

[scopes.p]
label = "personal"
paths = ["~/mywork"]
editor = "code"

[scopes.w]
label = "work"
paths = ["~/work"]
editor = "code"

[scopes.py]
label = "python"
paths = ["~/dev/python", "~/src/python"]
editor = "nvim"
depth = 2
excludes = [".venv", "__pycache__"]
include_workspaces = false

[scopes.js]
label = "javascript"
paths = ["~/dev/js", "~/src/js"]
editor = "code"
excludes = ["node_modules", ".git", "dist"]
```

## Optional Dependencies

- [fd](https://github.com/sharkdp/fd) — fast file search
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder
- [tree](http://mama.indstate.edu/users/ice/tree/) — directory preview

If missing, falls back to built-in alternatives.

## Platform Support

- Linux, macOS, Windows (with zsh via WSL, MSYS2, Cygwin, or Git Bash)

## License

MIT
