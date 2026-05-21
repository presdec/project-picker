# Project Picker — Visual Walkthrough

A demo for every feature. All recordings use real project structures with fzf + tree preview enabled unless noted.

---

## First-time setup

Run the interactive config wizard to define your scopes, paths, editors, and exclude presets. Project types are auto-detected.

![Setup wizard](https://github.com/presdec/project-picker/releases/download/v2.0.0/setup.gif)

Verify your config and optional dependencies are wired up correctly:

![Doctor check](https://github.com/presdec/project-picker/releases/download/v2.0.0/doctor.gif)

---

## Picking projects

### Fuzzy filter within a scope

`pw` opens your work scope. Type to filter — fzf narrows the list live with a tree preview on the right.

![Scope filter](https://github.com/presdec/project-picker/releases/download/v2.0.0/scope-filter.gif)

### Pick across all scopes

`p` aggregates every scope into one list.

![All scopes](https://github.com/presdec/project-picker/releases/download/v2.0.0/filter.gif)

---

## Editor integration

### Open in VS Code (default)

Select a project and it opens in your configured editor.

![Open in VS Code](https://github.com/presdec/project-picker/releases/download/v2.0.0/open-vscode.gif)

### Override editor per pick

`pw -e nvim` opens the selected project in Neovim regardless of scope config.

![Open in Neovim](https://github.com/presdec/project-picker/releases/download/v2.0.0/open-editor.gif)

---

## cd mode

`pw -d` changes your working directory instead of opening an editor. Useful for scripting or when you just want a shell in the project.

![cd mode](https://github.com/presdec/project-picker/releases/download/v2.0.0/cd-mode.gif)

---

## Latest shortcut

`pwl` reopens the last project you picked in the work scope — no picker, instant jump. `pwl -d` does the same but cds into it.

![Open latest](https://github.com/presdec/project-picker/releases/download/v2.0.0/open-latest.gif)

---

## Config

`p --config` writes a clean TOML with scopes, paths, editors, and exclude lists.

![Config reveal](https://github.com/presdec/project-picker/releases/download/v2.0.0/config-fast.gif)

---

## Full flow

Picking from work scope, jumping to an OSS scope with cd, then returning instantly with the latest shortcut.

![Full flow](https://github.com/presdec/project-picker/releases/download/v2.0.0/full-flow.gif)

---

## Works without optional dependencies

No fzf, no fd, no tree — the plugin falls back to a pure-zsh interactive TUI and `find` for project discovery. Same filtering, no external deps required.

![No deps fallback](https://github.com/presdec/project-picker/releases/download/v2.0.0/fallback-no-deps.gif)
