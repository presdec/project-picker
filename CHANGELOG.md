# Changelog

All notable changes to this project will be documented in this file.

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
