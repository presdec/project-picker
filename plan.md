# project-picker: Harden, Clean, oh-my-zsh Ready

## What was done

Ten commits improving robustness, oh-my-zsh compatibility, and UX. All changes are in `project-picker.plugin.zsh`, `completions/`, `README.md`, and `.github/workflows/ci.yml`.

---

## Commits

### `f427d08` fix: add missing `_pp_warn`/`_pp_die` helpers

`_pp_warn` and `_pp_die` were called throughout the plugin but never defined — all error messages were silently dropped.

Added after the color variable block:
```zsh
_pp_warn() { print -r -- "project-picker: $*" >&2; }
_pp_die()  { print -r -- "project-picker: error: $*" >&2; }
```

---

### `87a18f4` fix: capture plugin dir at source time for oh-my-zsh compatibility

`${0:A:h}` inside a zsh function returns the function name, not the sourced file path. This broke `p config`, `p doctor`, and `p reload` when loaded via oh-my-zsh.

Fix: capture at source time using `%x` (gives the sourced file path):
```zsh
typeset -g __PP_PLUGIN_DIR="${${(%):-%x}:A:h}"
```

Also adds dedup-guarded fpath setup so completions load automatically:
```zsh
if [[ -d "${__PP_PLUGIN_DIR}/completions" ]] && (( ! ${fpath[(I)${__PP_PLUGIN_DIR}/completions]} )); then
  fpath=("${__PP_PLUGIN_DIR}/completions" $fpath)
fi
```

`p_reload`, `p_doctor`, `p_config` all updated to use `$__PP_PLUGIN_DIR`.

---

### `e5766e0` feat: rename `-t` flag to `-d` (cd mode)

The "cd into project" flag was renamed from `-t` to `-d` (more intuitive — d for directory).

Changed in: `_pp_help`, `p()` getopts, `_pp_define_scope_cmds` eval block (both `p$k` and `p${k}l`), CI tests, README.

Usage:
```zsh
pw -d   # cd into selected work project
pp -d   # cd into selected personal project
p -d    # cd into any project
```

---

### `93c55d2` fix: harden `_pp_open` cd path

Old code: silently tried `$(dirname "$sel")` on failure with no feedback.

New `cd)` branch:
- Uses `${sel:h}` (zsh modifier, no subshell) instead of `$(dirname)`
- Checks target directory exists before attempting cd
- Emits `_pp_warn` with clear message on failure
- Uses `builtin cd -- "$_cd_target"` (guards paths starting with `-`)

```zsh
cd)
  local _cd_target
  if [[ -d "$sel" ]]; then
    _cd_target="$sel"
  else
    _cd_target="${sel:h}"
  fi
  if [[ ! -d "$_cd_target" ]]; then
    _pp_warn "directory not found: $_cd_target"
    return 1
  fi
  builtin cd -- "$_cd_target" || { _pp_warn "cd failed: $_cd_target"; return 1; }
  ;;
```

---

### `aa4897f` fix: three small hardening fixes

**1. `wc -l` whitespace trim** — on macOS, `wc -l < file` outputs leading spaces. Added `| tr -d ' \t'` to prevent arithmetic comparison issues in `_pp_log`.

**2. `PP_DEFINED_SCOPE_CMDS` global** — added `typeset -ga PP_DEFINED_SCOPE_CMDS` at file level so the array tracking generated scope functions persists reliably across reloads.

**3. Scope key sanitization** — in `_pp_load_toml`, scope keys extracted from TOML are now sanitized before use in `eval` (in `_pp_define_scope_cmds`):
```zsh
skey="${skey//[^a-zA-Z0-9]/}"
skey="${skey:l}"
[[ -z "$skey" ]] && continue
```

---

### `198c3cd` feat: invalidate cache when `config.toml` changes

Previously, editing `config.toml` (e.g., adding a new scope path) required waiting for the TTL to expire before seeing updated projects.

New helper `_pp_config_newer_than_cache` checks if the config was modified after the cache was built. Used alongside `_pp_is_cache_stale` in both `_pp_build_cache_for_key` and `_pp_build_cache_all`.

---

### `3312442` feat: add `completions/_p` zsh completion

New file `completions/_p` — tab completion for the `p` function:
- Completes subcommands: `config`, `doctor`, `reload`, `help`
- Completes `-d` flag (cd mode)
- Completes `-e` flag with editor list: `code codium idea cursor windsurf nvim vim`

Loaded automatically via the fpath setup added in `87a18f4`.

---

### `42797d9` docs: add oh-my-zsh/zinit install section

New `## Installation` section in README before Quick Start:

**oh-my-zsh (Custom Plugin):**
```sh
git clone https://github.com/presdec/project-picker \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/project-picker
```
Add `project-picker` to `plugins=(...)` in `~/.zshrc`.

**zinit:**
```sh
zinit light presdec/project-picker
```

---

### `30b2fe8` ci: add `bin/ppicker` syntax check

Added `zsh -n bin/ppicker` step to CI matrix alongside existing `zsh -n project-picker.plugin.zsh`.

---

### `86ab99a` docs: document `-d` and `-e` flags in README

Added to Commands/Options section so users can discover flags without reading source or help text.

---

## Testing in WSL/zsh

```zsh
# Syntax checks
zsh -n project-picker.plugin.zsh
zsh -n bin/ppicker
zsh -n completions/_ppicker
zsh -n completions/_p

# Source and verify self-path capture
source project-picker.plugin.zsh
echo $__PP_PLUGIN_DIR   # should be absolute path to plugin dir

# Verify helpers defined
_pp_warn "test"         # should print to stderr
_pp_die "test"          # should print to stderr

# Verify -d flag works (cd mode)
# set up a test project dir first:
mkdir -p /tmp/testproject
# add it to config, then:
pp -d   # should cd into selected project

# Verify p config / p doctor work (uses __PP_PLUGIN_DIR)
p doctor

# Verify completions load
fpath=(completions $fpath)
autoload -Uz compinit && compinit
p <TAB>   # should offer: config, doctor, reload, help, -d, -e

# Verify oh-my-zsh install path
git clone . ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/project-picker 2>/dev/null || true
# Add to plugins=() and source ~/.zshrc, then test p / p config
```

## Files changed

| File | Changes |
|------|---------|
| `project-picker.plugin.zsh` | Bug fixes + hardening (all tasks) |
| `completions/_p` | New file — `p` function completion |
| `README.md` | Installation section, flag docs |
| `.github/workflows/ci.yml` | Syntax check for `bin/ppicker`, `-d` flag in tests |
