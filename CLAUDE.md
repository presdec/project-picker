# project-picker

Zsh plugin + CLI for fuzzy project switching. No build system, no package manager.

## Stack

- **Language**: zsh only
- **Main plugin**: `project-picker.plugin.zsh`
- **CLI**: `bin/ppicker`
- **Config**: TOML at `$XDG_CONFIG_HOME/project-picker/config.toml` (default `~/.config/project-picker/config.toml`)
- **Optional deps**: `fd`, `fzf`, `tree` (fall back to `find`, menu, none)

## Commands

```zsh
# Syntax check (fast)
zsh -n project-picker.plugin.zsh

# CLI
zsh bin/ppicker init          # interactive config wizard
zsh bin/ppicker init --defaults  # non-interactive (CI); set PPICKER_SCOPE_PATH + PPICKER_SCOPE_LABEL
zsh bin/ppicker doctor        # validate config + deps
zsh bin/ppicker --version

# Plugin (after sourcing)
p                   # pick from all scopes
p<key>              # pick in scope (pw, pp, etc.)
p<key>l             # open last in scope
p --config / p --doctor / p --reload
```

## Testing

No local test runner. Tests live in `.github/workflows/ci.yml` (Ubuntu + macOS).

Non-interactive test pattern:
```zsh
export PP_FZF_FILTER=audio
sel="$(_pp_pick_from_list "/path/a" "/path/b")"
test "$sel" = "/path/a"
```

Smoke test locally:
```zsh
zsh -n project-picker.plugin.zsh
PPICKER_SCOPE_PATH=/tmp/work PPICKER_SCOPE_LABEL=work zsh bin/ppicker init --defaults
zsh bin/ppicker doctor
```

## Key env vars

| Var | Purpose |
|-----|---------|
| `PP_CACHE_DIR` | Override cache dir (default `~/.cache/project-picker`) |
| `PP_LOG_FILE` | Override history log |
| `PP_FZF_FILTER` | Non-interactive fzf filter (for tests) |
| `PP_PREVIEW_SHELL` | Shell for fzf previews |
| `PPICKER_SCOPE_PATH` | Path for `--defaults` init |
| `PPICKER_SCOPE_LABEL` | Label for `--defaults` init |
| `XDG_CONFIG_HOME` | Config base dir |

## Code map

- `_pp_load_toml` — parse config.toml into `PP_SCOPE_*` assoc arrays
- `_pp_build_cache_for_key` / `_pp_build_cache_all` — project listing + cache
- `_pp_list_projects_one_root` — `fd` or `find` fallback
- `_pp_pick_from_list` — `fzf` or menu fallback
- `_pp_define_scope_cmds` — dynamically generates `p<key>` / `p<key>l` functions
- `p()` — main entry point and canonical user-facing command
- `bin/ppicker` — standalone/backend CLI (init wizard, doctor, reload)
