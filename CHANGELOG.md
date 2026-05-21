# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-05-21

### Breaking Changes

- Renamed cd mode from `-t` to `-d` for `p`, `p<key>`, and `p<key>l`.
- Standardized the user-facing management commands around `p --config`, `p --doctor`, and `p --reload`. The old `p config`, `p init`, `p doctor`, and `p reload` forms remain as compatibility aliases.

### Added

- Multi-path scope setup in the interactive config wizard, including path suggestions, manual entry, filesystem search, and optional fzf browsing.
- Exclude presets for common stacks (`web`, `python`, `rust`, `go`, `jvm`, `dotnet`, `ruby`, `php`, `cpp`, `elixir`, `dart`, `swift`, `mobile`) with automatic project-type detection.
- `p` zsh completion for canonical management flags, compatibility subcommands, `-d`, and `-e <editor>`.
- `p init` compatibility alias for the config wizard.
- `fdfind` fallback for Debian/Ubuntu systems where `fd` is installed under that name.

### Changed

- Made `p` the canonical interactive command and clarified `ppicker` as the standalone/backend CLI for scripts and plugin bridging.
- Updated `p --help`, README, completions, and CLI guidance to use `p --config`, `p --doctor`, and `p --reload`.
- Improved config wizard validation for scope keys, duplicate scopes, TTL, depth, and path selection.
- Expanded README installation guidance for oh-my-zsh, zinit, manual installs, command usage, TOML schema, exclude presets, and CI behavior.
- Added README badges for CI, release workflow, latest release, license, zsh, and platform support.
- Added contributor, security, pull request, and issue templates.
- Broadened CI smoke coverage for plugin syntax, CLI syntax, cache behavior, excludes, depth handling, workspace files, `p -d`, canonical management flags, compatibility aliases, and oh-my-zsh custom plugin loading.
- Updated release artifacts to include both `p` and `ppicker` completions plus the changelog.

### Fixed

- Captured the plugin directory at source time so `p --config`, `p --doctor`, and `p --reload` work when loaded through oh-my-zsh and similar plugin managers.
- Added missing `_pp_warn` and `_pp_die` helpers so errors are visible instead of silently dropped.
- Hardened cd mode with zsh path handling, directory existence checks, and clear error messages.
- Invalidated project caches when `config.toml` is newer than the cached list.
- Reset generated scope command state during reloads so stale scope functions are removed.
- Sanitized TOML scope keys before generating shell functions.
- Parsed TOML arrays, quoted strings, and inline comments more reliably.
- Trimmed `wc -l` output before arithmetic comparisons for better macOS compatibility.
- Improved `find` fallback pruning and depth handling when optional dependencies are unavailable.

---

## [1.0.0] - 2025-09-17

### Changed

- Introduced automated GitHub Release workflow to package and publish artifacts.

### Fixed

- Document preview pane now renders reliably and behaves as expected.

### Docs

- Added README screencast image.

---

## [1.0.0-beta] - 2025-09-09

### Pre-release

- First beta pre-release tagged as `v1.0.0-beta`.
- Cross-platform CI (Ubuntu, macOS) added with integration tests for plugin and CLI.
- Non-interactive `ppicker init --defaults` for CI and automation.
- Numerous portability fixes for zsh and BSD/GNU utilities.

---

## [0.9.0] - 2025-09-05

### Added

- `history_max_lines` config option (default 1000) in `[global]` section
- Log file is trimmed to newest N lines if exceeded
- Doctor reports current history_max_lines value
- Initial public release
- Interactive config wizard (`ppicker init`, `p config`)
- Per-scope and global TOML config
- Auto-generated scope commands (`p`, `p<key>`, `p<key>l`, etc.)
- Editor/preview integration
- Optional dependencies: fd, fzf, tree
- Zsh completion for CLI
- Reload command (`ppicker reload`, `p reload`)
- Doctor command for config validation
- Rich README with schema and examples

### Changed

- Improved error reporting in doctor
- Help output aligned between plugin and CLI

### Fixed

- Suppressed debug traces in all modes
- Robust path expansion and validation

---

## Tagging (SemVer)

- Use tags like `v1.0.0`, `v1.1.0`, `v2.0.0` for releases.
- Update this changelog for every new tag/release.
