# Project Picker

[![CI](https://github.com/presdec/project-picker/actions/workflows/ci.yml/badge.svg)](https://github.com/presdec/project-picker/actions/workflows/ci.yml)
[![Release](https://github.com/presdec/project-picker/actions/workflows/release.yml/badge.svg)](https://github.com/presdec/project-picker/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/presdec/project-picker?sort=semver)](https://github.com/presdec/project-picker/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell: zsh](https://img.shields.io/badge/shell-zsh-89e051.svg)](https://www.zsh.org/)
[![Platforms](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#platform-support)

Jump between repos instantly from your terminal. Supports multiple scopes, fuzzy search, and editor integration.

![Screencast_20250917_082517 (1)](https://github.com/user-attachments/assets/cbf8c885-a6b5-483a-b70b-b9a5ef27f849)

## Features

- Define scopes for different project roots (work, personal, language, etc.)
- Fuzzy or menu-based project selection (fzf optional)
- Editor and preview integration
- Per-scope and global config via TOML
- Auto-generates commands: `p`, `p<key>`, `p<key>l`, `ppl`, `pwl`, etc.
- Optional dependencies: `fd`, `fzf`, `tree` (falls back to built-ins)
- Works on Linux, macOS, and Windows (with zsh)

## Installation

### oh-my-zsh (Custom Plugin)

Clone into your custom plugins directory:

```sh
git clone https://github.com/presdec/project-picker \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/project-picker
```

Add `project-picker` to your plugins array in `~/.zshrc`:

```sh
plugins=(... project-picker)
```

Restart your shell (or `source ~/.zshrc`), then run the setup wizard:

```sh
p --config
```

### zinit

```sh
zinit light presdec/project-picker
```

### Manual

Add to `~/.zshrc`:

```sh
source /path/to/project-picker/project-picker.plugin.zsh
```

Then run `p --config` to set up scopes.

## Quick Start

1. Install the plugin (see [Installation](#installation) for oh-my-zsh, zinit, and manual options).
2. Run the config wizard:
   ```sh
   p --config
   ```
   - Non-interactive (for CI):
     ```sh
     PPICKER_SCOPE_PATH="$HOME/work" PPICKER_SCOPE_LABEL="work" ppicker init --defaults
     ```
3. Validate config:
   ```sh
   p --doctor
   ```
4. Pick a project:
   ```sh
   p
   # or for a scope: pw, pp, etc.
   # open last: pwl, ppl
   ```

## Commands

- `p --config` — run config wizard
- `p --doctor` — validate config and dependencies
- `p --reload` — reload plugin functions after config change
- `p` — pick a project from any scope
- `p<key>` — pick in a specific scope (e.g. `pw`, `pp`, `py`, `js`)
- `p<key>l` — open last in scope (e.g. `pwl`, `ppl`, `pyl`, `jsl`)
- `p config`, `p init`, `p doctor`, `p reload` — compatibility aliases

Options:
  -d                      cd into project instead of opening in editor
  -e <editor>             Override editor (code|idea|cursor|windsurf|nvim|vim|codium|custom:/path)
  --config                Run config wizard
  --doctor                Validate config and dependencies
  --reload                Reload plugin functions
  --help                  Show this help

### Backend CLI

`ppicker` is the standalone/backend CLI for scripts and plugin bridging:

- `ppicker init` — run config wizard
- `ppicker init --defaults` — non-interactive setup for CI/automation. Set `PPICKER_SCOPE_PATH` and `PPICKER_SCOPE_LABEL` to control the generated default scope.
- `ppicker doctor` — validate config and dependencies
- `ppicker reload` — show backend reload guidance
- `ppicker --help`, `ppicker --version`

## Configuration

- Config file: `$XDG_CONFIG_HOME/project-picker/config.toml` or `$HOME/.config/project-picker/config.toml`
- Use `p --config` to set up scopes, editors, one or more paths per scope, excludes, etc.
- `history_max_lines` (in `[global]`) sets the maximum number of lines kept in the history log (default: 1000). If the log exceeds this, it is trimmed to the newest N lines automatically.
- During setup, project type markers are detected under each scope path and used to suggest exclude presets. Presets can also be combined manually per scope, such as `web,python`, `rust`, `all`, `none`, or `custom`. Presets only write a normal `excludes = [...]` array to the config.

### Detected exclude presets

The setup wizard does a shallow scan under each scope path and suggests exclude presets from common project markers. Detection is advisory: press Enter to accept the suggestion, or type any preset combo such as `default,web,python`, `none`, `all`, or `custom`.

| Preset | Markers |
| --- | --- |
| `web` | `package.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb` |
| `python` | `pyproject.toml`, `requirements.txt`, `setup.py`, `uv.lock` |
| `rust` | `Cargo.toml` |
| `go` | `go.mod` |
| `jvm` | `pom.xml`, `build.gradle`, `build.gradle.kts`, `settings.gradle`, `settings.gradle.kts` |
| `dotnet` | `*.csproj`, `*.sln` |
| `ruby` | `Gemfile` |
| `php` | `composer.json` |
| `cpp` | `CMakeLists.txt` |
| `elixir` | `mix.exs` |
| `dart` | `pubspec.yaml` |
| `swift` | `Package.swift` |
| `mobile` | `android/build.gradle`, `android/build.gradle.kts`, `ios/Pods` |

### Environment variables

- Picker/Plugin:
  - `PP_CACHE_DIR` — override cache directory (default: `$HOME/.cache/project-picker`).
  - `PP_LOG_FILE` — override history log path (default: `$PP_CACHE_DIR/history.log`).
  - `PP_PREVIEW_SHELL` — shell used for fzf previews (default: `/bin/sh`).
  - `PP_FZF_FILTER` — non-interactive filter passed to fzf (used in tests/automation).
- CLI (`ppicker init --defaults`):
  - `PPICKER_SCOPE_PATH` — path for the default scope (default: `$HOME/work`).
  - `PPICKER_SCOPE_LABEL` — label for the default scope (default: `work`).
  - `XDG_CONFIG_HOME` — base config directory (writes to `$XDG_CONFIG_HOME/project-picker/config.toml`).

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
- Use `excludes = []` to explicitly disable excludes for a scope.
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

- [fd](https://github.com/sharkdp/fd) or `fdfind` from Debian/Ubuntu `fd-find` — fast file search
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder
- [tree](http://mama.indstate.edu/users/ice/tree/) — directory preview

If missing, falls back to built-in alternatives.

## Continuous Integration

This repository runs cross-platform tests on Ubuntu and macOS via GitHub Actions.

- Non-interactive selection in tests is driven by `PP_FZF_FILTER`.
- The config file is generated non-interactively using `ppicker init --defaults`.
- The workflow also validates caching, exclude rules, depth handling, and both `p`/`p<key>` flows.

You can view the latest runs by clicking the CI badge above.

## Platform Support

- Linux, macOS, Windows (with zsh via WSL, MSYS2, Cygwin, or Git Bash)

## License

MIT
