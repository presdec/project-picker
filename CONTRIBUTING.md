# Contributing

Thanks for improving Project Picker. Keep changes focused and test behavior in zsh.

## Local Checks

Run syntax checks before opening or updating a pull request:

```sh
zsh -n project-picker.plugin.zsh
zsh -n bin/ppicker
zsh -n completions/_p
zsh -n completions/_ppicker
```

For picker behavior, prefer temporary config/cache paths so local user state is not touched:

```sh
export XDG_CONFIG_HOME=/tmp/project-picker-config
export PP_CACHE_DIR=/tmp/project-picker-cache
export PPICKER_SCOPE_PATH=/tmp/project-picker-work
export PPICKER_SCOPE_LABEL=work
mkdir -p "$XDG_CONFIG_HOME/project-picker" "$PPICKER_SCOPE_PATH"
zsh bin/ppicker init --defaults
source project-picker.plugin.zsh
p --doctor
```

## Compatibility

- Target zsh on Linux, macOS, and WSL.
- Keep optional dependencies optional: `fd`/`fdfind`, `fzf`, and `tree` must have fallbacks.
- Avoid Bash-only syntax in plugin and CLI code.
- Keep `p` as the canonical interactive command and `ppicker` as the backend/scriptable CLI.
- Preserve compatibility aliases unless a release explicitly documents their removal.

## Release Process

1. Update `CHANGELOG.md`.
2. Update `VERSION` in `bin/ppicker`.
3. Merge through a pull request with CI passing.
4. Tag from `master`, for example `git tag v2.0.0 && git push origin v2.0.0`.
5. Verify the GitHub Release contains the tarball and `.sha256` artifact.
