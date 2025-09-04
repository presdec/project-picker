# Project Picker

A fast, interactive project launcher for zsh. Supports multiple scopes, fuzzy search, and editor integration.

## Features
- Define scopes for different project roots (work, personal, etc.)
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
2. Run the config wizard:
   ```sh
   p config
   ```
3. Pick a project:
   ```sh
   p
   # or for a scope: pw, pp, etc.
   # open last: pwl, ppl
   ```

## Commands
- `p` — pick a project from any scope
- `p<key>` — pick in a specific scope (e.g. `pw`, `pp`)
- `p<key>l` — open last in scope (e.g. `pwl`, `ppl`)
- `p config` — run config wizard
- `p doctor` — validate config and dependencies

## Configuration
- Config file: `$XDG_CONFIG_HOME/project-picker/config.toml` or `$HOME/.config/project-picker/config.toml`
- Use `p config` to set up scopes, editors, excludes, etc.

## Optional Dependencies
- [fd](https://github.com/sharkdp/fd) — fast file search
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder
- [tree](http://mama.indstate.edu/users/ice/tree/) — directory preview

If missing, falls back to built-in alternatives.

## Platform Support
- Linux, macOS, Windows (with zsh via WSL, MSYS2, Cygwin, or Git Bash)

## License
MIT
