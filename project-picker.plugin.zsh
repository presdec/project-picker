# project-picker.plugin.zsh

# Defaults & Globals
unsetopt xtrace 2>/dev/null || true
unsetopt verbose 2>/dev/null || true
set +x +v 2>/dev/null || true
typeset -g PP_CACHE_TTL_MIN=10
typeset -g PP_DEFAULT_EDITOR=code
typeset -g PP_PREVIEW=tree
typeset -g PP_DEPTH=1
typeset -g PP_EXCLUDES="node_modules:.git"
typeset -g PP_INCLUDE_WORKSPACES=true
typeset -g PP_CACHE_DIR="${HOME}/.cache/project-picker"
typeset -g PP_LOG_FILE="${PP_CACHE_DIR}/history.log"
typeset -g PP_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/project-picker/config.toml"
typeset -g PP_HISTORY_MAX_LINES=1000

# --- helpers, colors, and preview shell ---
# Colors for announcements (safe defaults if terminal doesn’t support)
typeset -g PP_CLR_RESET=$'\e[0m'
typeset -g PP_CLR_DIM=$'\e[2m'
typeset -g PP_CLR_BOLD=$'\e[1m'
typeset -g PP_CLR_GREEN=$'\e[32m'
typeset -g PP_CLR_BLUE=$'\e[34m'

# Shell used for fzf preview scripts (keep minimal and universal)
typeset -g PP_PREVIEW_SHELL="${PP_PREVIEW_SHELL:-/bin/sh}"

# Quiet helpers (no-ops; kept for compatibility/hooks)
_pp_quiet_push() { :; }
_pp_quiet_pop()  { :; }

_pp_have() { command -v "$1" >/dev/null 2>&1; }
_pp_expand_tilde() { [[ "$1" == ~* ]] && echo ${~1} || echo "$1"; }
_pp_join_colon() { local IFS=:; print -r -- "$*"; }

_pp_bootstrap_fs() {
  mkdir -p -- "$PP_CACHE_DIR" 2>/dev/null || true
  [[ -r "$PP_LOG_FILE" ]] || : >| "$PP_LOG_FILE"
}

_pp_now_epoch() { date +%s 2>/dev/null; }
_pp_file_mtime_epoch() {
  local f="$1"
  [[ -e "$f" ]] || { echo 0; return; }
  if stat -c %Y "$f" >/dev/null 2>&1; then
    stat -c %Y "$f"
  else
    stat -f %m "$f"
  fi
}
_pp_is_cache_stale() {
  local f="$1" ttl_min="$2"
  [[ ! -s "$f" ]] && return 0
  local now mt ttl
  now="$(_pp_now_epoch)"
  mt="$(_pp_file_mtime_epoch "$f")"
  ttl=$(( ttl_min * 60 ))
  (( now - mt >= ttl )) && return 0 || return 1
}

_pp_icon_for() { case "$1" in cd) echo "📂";; custom) echo "🚀";; *) echo "🗂";; esac; }
_pp_label_for_action() { local a="$1" e="$2"; case "$a" in cd) echo cd;; custom) echo "${e:t:-editor}";; *) echo "VS Code";; esac; }
_pp_qpath() {
  local path_in="$1" leaf
  leaf="${path_in:t}"
  [[ "$leaf" == *.code-workspace ]] && leaf="${leaf%.code-workspace}"
  printf '"%s"' "$leaf"
}
_pp_announce() {
  local scope="$1" action="$2" editor="$3" path="$4"
  local icon label pstr
  icon="$(_pp_icon_for "$action")"
  label="$(_pp_label_for_action "$action" "$editor")"
  pstr="$(_pp_qpath "$path")"
  printf "${PP_CLR_GREEN}%s  Opened${PP_CLR_RESET} ${PP_CLR_BOLD}%s${PP_CLR_RESET} ${PP_CLR_DIM}with${PP_CLR_RESET} ${PP_CLR_BLUE}%s${PP_CLR_RESET} ${PP_CLR_DIM}(%s)${PP_CLR_RESET}\n" \
    "$icon" "$pstr" "$label" "$scope"
}

# Ensure no stray debug variables leak into shell (defensive)
unset -m 'tok' 2>/dev/null || true

# cross-platform editor launcher
_pp_run_editor() {
  local editor="$1" target="$2" sys="${OSTYPE:-}"
  case "$editor" in
    code)
      if command -v code >/dev/null 2>&1; then command code -- "$target"
      elif [[ "$sys" == darwin* ]]; then open -a "Visual Studio Code" -- "$target"
      else command code -- "$target"
      fi
      ;;
    codium)
      if command -v codium >/dev/null 2>&1; then command codium -- "$target"
      elif [[ "$sys" == darwin* ]]; then open -a "VSCodium" -- "$target"
      else command codium -- "$target"
      fi
      ;;
    cursor)
      if command -v cursor >/dev/null 2>&1; then command cursor -- "$target"
      elif [[ "$sys" == darwin* ]]; then open -a "Cursor" -- "$target"
      else command cursor -- "$target"
      fi
      ;;
    windsurf)
      if command -v windsurf >/dev/null 2>&1; then command windsurf -- "$target"
      elif [[ "$sys" == darwin* ]]; then open -a "Windsurf" -- "$target"
      else command windsurf -- "$target"
      fi
      ;;
    idea)
      if command -v idea >/dev/null 2>&1; then command idea -- "$target"
      elif [[ "$sys" == darwin* ]]; then open -a "IntelliJ IDEA" -- "$target" || open -a "IntelliJ IDEA CE" -- "$target"
      else command idea -- "$target"
      fi
      ;;
    nvim|vim)
      command "$editor" -- "$target"
      ;;
    custom:*)
      local cmd="${editor#custom:}"
      command "$cmd" -- "$target"
      ;;
    *)
      if [[ -n "$PP_DEFAULT_EDITOR" && "$editor" != "$PP_DEFAULT_EDITOR" ]]; then
        _pp_run_editor "$PP_DEFAULT_EDITOR" "$target"
      elif command -v code >/dev/null 2>&1; then
        command code -- "$target"
      elif [[ "$sys" == darwin* ]]; then
        open -a "Visual Studio Code" -- "$target"
      else
        _pp_warn "no editor available: $editor"; return 1
      fi
      ;;
  esac
}

_pp_require() {
  local missing=()
  _pp_have fd   || missing+=("fd")
  _pp_have fzf  || missing+=("fzf")
  if [[ "$PP_PREVIEW" == "tree" ]] && ! _pp_have tree; then missing+=("tree"); fi
  (( ${#missing[@]} )) && _pp_warn "missing: ${missing[*]}  (falls back automatically)"
}

_pp_cache() { echo "$PP_CACHE_DIR/projects.$1.list"; }
_pp_last()  { echo "$PP_CACHE_DIR/last.$1"; }
_pp_log() {
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf '%s\t%s\t%s\t%s\n' "$ts" "$1" "$2" "$3" >> "$PP_LOG_FILE"
  local max_lines="${PP_HISTORY_MAX_LINES:-1000}"
  local cur_lines
  cur_lines=$(wc -l < "$PP_LOG_FILE" 2>/dev/null)
  if [[ -n "$cur_lines" && "$cur_lines" -gt "$max_lines" ]]; then
    tail -n "$max_lines" "$PP_LOG_FILE" > "$PP_LOG_FILE.tmp" && mv "$PP_LOG_FILE.tmp" "$PP_LOG_FILE"
  fi
}
ph()  { command tail -n "${1:-50}" "$PP_LOG_FILE" 2>/dev/null | sed 's/\t/  |  /g'; }
phg() { command grep -i -- "$1" "$PP_LOG_FILE" 2>/dev/null | sed 's/\t/  |  /g'; }
phc() { : >| "$PP_LOG_FILE"; echo "history cleared: $PP_LOG_FILE"; }

# TOML Loader
_pp_load_toml() {
  emulate -L zsh
  setopt localoptions no_auto_name_dirs
  unsetopt xtrace verbose
  # Reset scope maps to avoid stale keys lingering across reloads
  typeset -gA PP_SCOPE_PATHS PP_SCOPE_LABELS PP_SCOPE_EDITORS PP_SCOPE_DEPTH PP_SCOPE_EXCLUDES PP_SCOPE_INCLUDE_WS
  PP_SCOPE_PATHS=()
  PP_SCOPE_LABELS=()
  PP_SCOPE_EDITORS=()
  PP_SCOPE_DEPTH=()
  PP_SCOPE_EXCLUDES=()
  PP_SCOPE_INCLUDE_WS=()
  local cfg="$PP_CONFIG_FILE"
  if [[ ! -f "$cfg" ]]; then
    PP_SCOPE_PATHS=( [w]="$HOME/work" [p]="$HOME/mywork" )
    PP_SCOPE_LABELS=( [w]="work" [p]="personal" )
    PP_SCOPE_EDITORS=( [w]="$PP_DEFAULT_EDITOR" [p]="$PP_DEFAULT_EDITOR" )
    PP_HISTORY_MAX_LINES=1000
    return 0
  fi
  local section="" key="" line k v raw
  while IFS= read -r line; do
    line="${line%%\#*}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" == \[*\] ]]; then
      section="${line#\[}"; section="${section%\]}"
      continue
    fi
    if [[ "$line" == *"="* ]]; then
      k="${line%%=*}"; v="${line#*=}"
      k="${k//[[:space:]]/}"
      v="${v##[[:space:]]}"
      if [[ "$section" == "global" ]]; then
        case "$k" in
          history_max_lines)    PP_HISTORY_MAX_LINES="${v//[[:space:]]/}" ;;
          cache_ttl_min)        PP_CACHE_TTL_MIN="${v//[[:space:]]/}" ;;
          default_editor)       PP_DEFAULT_EDITOR="${v//\"/}" ;;
          preview)              PP_PREVIEW="${v//\"/}" ;;
          depth)                PP_DEPTH="${v//[[:space:]]/}" ;;
          include_workspaces)   PP_INCLUDE_WORKSPACES="${v//[[:space:]]/}" ;;
          excludes)
            raw="${v#\[}"; raw="${raw%\]}"; raw="${raw//\"/}"; raw="${raw// /}"
            PP_EXCLUDES="${raw//,/":"}"
            ;;
        esac
        continue
      fi
      if [[ "$section" == scopes.* ]]; then
        local skey="${section#scopes.}"
        case "$k" in
          label)   PP_SCOPE_LABELS[$skey]="${v//\"/}" ;;
          editor)  PP_SCOPE_EDITORS[$skey]="${v//\"/}" ;;
          depth)   PP_SCOPE_DEPTH[$skey]="${v//[[:space:]]/}" ;;
          include_workspaces) PP_SCOPE_INCLUDE_WS[$skey]="${v//[[:space:]]/}" ;;
          excludes)
            raw="${v#\[}"; raw="${raw%\]}"; raw="${raw//\"/}"; raw="${raw// /}"
            PP_SCOPE_EXCLUDES[$skey]="${raw//,/":"}"
            ;;
          paths)
            raw="${v#\[}"; raw="${raw%\]}"; raw="${raw//\"/}"
            local -a parts=() expanded=()
            IFS=',' read -A parts <<< "$raw"
            local tok
            for tok in "${parts[@]}"; do
              tok="${tok## }"; tok="${tok%% }"
              [[ -z "$tok" ]] && continue
              expanded+=("$(_pp_expand_tilde "$tok")")
            done
            PP_SCOPE_PATHS[$skey]="$(_pp_join_colon "${expanded[@]}")"
            ;;
        esac
        continue
      fi
    fi
  done < "$cfg"
  local sk
  for sk in "${(@k)PP_SCOPE_PATHS}"; do
    [[ -n "${PP_SCOPE_LABELS[$sk]}" ]]  || PP_SCOPE_LABELS[$sk]="$sk"
    [[ -n "${PP_SCOPE_EDITORS[$sk]}" ]] || PP_SCOPE_EDITORS[$sk]="$PP_DEFAULT_EDITOR"
  done
}

# Project Listing
_pp_exclude_args_fd_array() {
  reply=()
  local X="$1" x IFS=:
  for x in $X; do
    [[ -n "$x" ]] && reply+=( -E "$x" )
  done
}
_pp_exclude_args_find_array() {
  reply=()
  local X="$1" x IFS=:
  for x in $X; do
    [[ -n "$x" ]] && reply+=( -not -path "*/$x/*" )
  done
}

_pp_list_projects_one_root() {
  local root="$1" depth="$2" include_ws="$3" excludes="$4"
  if _pp_have fd; then
    local -a ex; _pp_exclude_args_fd_array "$excludes"; ex=("${reply[@]}")
    fd -a -t d -d "$depth" . "$root" "${ex[@]}"
    if [[ "$include_ws" == "true" || "$include_ws" == "1" ]]; then
      fd -a -t f -d "$depth" --extension code-workspace . "$root" "${ex[@]}"
    fi
  else
    # Portable fallback for BSD (macOS) and GNU: no -maxdepth, filter by slash count
    local -a exf; _pp_exclude_args_find_array "$excludes"; exf=("${reply[@]}")
  local root_clean="$root"
  [[ "$root_clean" == */ ]] && root_clean="${root_clean%/}"
  local base_slashes_str="${root_clean//[^/]/}"
    local base_slashes
    base_slashes=${#base_slashes_str}
    local max_slashes=$(( base_slashes + depth ))
    # Directories up to depth
    command find "$root_clean" -type d "${exf[@]}" \
      | awk -v md="$max_slashes" '{n=gsub(/\//,"&"); if (n<=md) print $0}'
    # Workspace files up to depth
    if [[ "$include_ws" == "true" || "$include_ws" == "1" ]]; then
      command find "$root_clean" -type f -name '*.code-workspace' "${exf[@]}" \
        | awk -v md="$max_slashes" '{n=gsub(/\//,"&"); if (n<=md) print $0}'
    fi
  fi
}

_pp_build_cache_for_key() {
  local key="$1"
  local cache="$(_pp_cache "$key")"
  local depth="${PP_SCOPE_DEPTH[$key]:-$PP_DEPTH}"
  local incws="${PP_SCOPE_INCLUDE_WS[$key]:-$PP_INCLUDE_WORKSPACES}"
  local excludes="${PP_SCOPE_EXCLUDES[$key]:-$PP_EXCLUDES}"

  if _pp_is_cache_stale "$cache" "$PP_CACHE_TTL_MIN"; then
    : >| "$cache"
    local paths="${PP_SCOPE_PATHS[$key]}"
    local r; local IFS=:
    for r in $paths; do
      [[ -d "$r" ]] || continue
      _pp_list_projects_one_root "$r" "$depth" "$incws" "$excludes" >> "$cache"
    done
  fi
  echo "$cache"
}

_pp_build_cache_all() {
  local cache="$(_pp_cache all)"
  if _pp_is_cache_stale "$cache" "$PP_CACHE_TTL_MIN"; then
    : >| "$cache"
    local k
    for k in "${(@k)PP_SCOPE_PATHS}"; do
      cat "$(_pp_build_cache_for_key "$k")" >> "$cache"
    done
  fi
  echo "$cache"
}

# Picker (fzf or menu) — robust against env/aliases and spaces/tabs
_pp_pick_from_list() {
  emulate -L zsh
  setopt localoptions noshwordsplit pipefail

  local -a src; src=("$@")
  (( ${#src[@]} )) || return 1

  local -a lines labels paths
  local it leaf safe_it i=1
  for it in "${src[@]}"; do
    leaf="${it:t}"
    [[ "$leaf" == *.code-workspace ]] && leaf="${leaf%.code-workspace}"
    leaf="${leaf//$'\t'/ }"      # guard tabs in label
    safe_it="${it//$'\t'/ }"     # guard tabs in path
    lines+=("$i"$'\t'"$leaf"$'\t'"$safe_it")
    labels+=("$leaf")
    paths+=("$safe_it")
    ((i++))
  done

  if _pp_have fzf; then
    local selected
    if [[ "$PP_PREVIEW" == "tree" && $(_pp_have tree; echo $?) -eq 0 ]]; then
      selected=$(printf '%s\n' "${lines[@]}" \
        | command env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -- fzf \
            --no-multi --ansi --delimiter $'\t' --with-nth=2..2 --nth=2..2 \
            --prompt="Project > " --height=80% --layout=reverse --border \
            --preview="$PP_PREVIEW_SHELL -c 'p=\$(printf \"%s\" \"\$1\" | cut -d \$'\''\t'\'' -f3-); if [ -d \"\$p\" ]; then tree -a -L 2 \"\$p\"; else echo \".code-workspace:\"; head -n 120 \"\$p\"; fi' _ {}"
      ) || return 1
    else
      selected=$(printf '%s\n' "${lines[@]}" \
        | command env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -- fzf \
            --no-multi --ansi --delimiter $'\t' --with-nth=2..2 --nth=2..2 \
            --prompt="Project > " --height=80% --layout=reverse --border \
            --preview="$PP_PREVIEW_SHELL -c 'p=\$(printf \"%s\" \"\$1\" | cut -d \$'\''\t'\'' -f3-); name=\$(basename \"\$p\"); typ=dir; [ -d \"\$p\" ] || typ=file; echo \"Name:  \$name\"; echo \"Path:  \$p\"; if [ -r \"$PP_LOG_FILE\" ]; then last=\$(grep -F -- \"\$p\" \"$PP_LOG_FILE\" 2>/dev/null | tail -n 1 | cut -f1); [ -n \"\$last\" ] && echo \"Last:  \$last\"; fi; echo; if [ \"\$typ\" = dir ]; then ls -1a \"\$p\" | head -n 30; else head -n 120 \"\$p\"; fi' _ {}"
      ) || return 1
    fi
    printf '%s\n' "$selected" | cut -d $'\t' -f3-
  else
    # Minimal interactive filter when fzf is unavailable
    local -a fi_labels fi_paths
    integer i
    for (( i=1; i<=${#labels[@]}; i++ )); do
      fi_labels+=("${labels[$i]}")
      fi_paths+=("${paths[$i]}")
    done
    while true; do
      local idx=1
      for leaf in "${fi_labels[@]}"; do printf '%2d) %s\n' $idx "$leaf"; ((idx++)); done
      printf "Select number, /text to filter, or q: "
      local ans; read -r ans
      [[ "$ans" == q ]] && return 1
      if [[ "$ans" == /* ]]; then
        local q="${ans#/}" ql; ql="${q:l}"
        fi_labels=() fi_paths=()
        for (( i=1; i<=${#labels[@]}; i++ )); do
          local ll="${labels[$i]}"
          [[ "${ll:l}" == *${ql}* ]] || continue
          fi_labels+=("$ll")
          fi_paths+=("${paths[$i]}")
        done
        (( ${#fi_labels[@]} )) || printf "(no matches)\n"
        continue
      fi
      if [[ -n "$ans" && "$ans" == <-> ]]; then
        local n=$ans
        if (( n>=1 && n<=${#fi_paths[@]} )); then
          print -r -- "${fi_paths[$n]}"
          return 0
        fi
      fi
      printf "Invalid input.\n"
    done
  fi
}

# Scope Helpers
_pp_key_for_path() {
  local sel="$1" k paths r
  for k in "${(@k)PP_SCOPE_PATHS}"; do
    paths="${PP_SCOPE_PATHS[$k]}"
    local IFS=:
    for r in $paths; do
      [[ -n "$r" && "$sel" == "$r"* ]] && { echo "$k"; return; }
    done
  done
  echo ""
}

_pp_help() {
  print -r -- "Project Picker:"
  print -r -- "  p [options]             Prompt for scope or 'all', pick, open"
  print -r -- "  p<key> [options]        Pick in scope (e.g. pw, pp, pr, pt)"
  print -r -- "  p<key>l [options]       Open last in scope (e.g. pwl, ppl, prl)"
  print -r -- "  ppl, pwl                Open last personal/work project (if scopes 'p' and 'w' exist)"
  print -r -- "  p config                Run config wizard (interactive setup)"
  print -r -- "  p doctor                Validate config and dependencies"
  print -r -- "  p reload                Reload config and regenerate plugin functions"
  print -r -- "Options:"
  print -r -- "  -t                      cd into project instead of opening"
  print -r -- "  -e <editor>             Override editor (code|idea|cursor|windsurf|nvim|vim|codium|custom:/path)"
  print -r -- "  --help                  Show this help"
  print -r -- "Config: ${PP_CONFIG_FILE}"
}

# Reloader and CLI bridge
p_reload() {
  local self
  self="${(%):-%N}"
  if [[ -r "$self" ]]; then
    { emulate -L zsh; setopt localoptions; unsetopt xtrace verbose; source "$self"; } >/dev/null 2>&1
  else
    { emulate -L zsh; setopt localoptions; unsetopt xtrace verbose; source "$PP_CONFIG_FILE:h/../project-picker.plugin.zsh"; } >/dev/null 2>&1
  fi
  print -r -- "Project Picker plugin reloaded."
}
p_doctor() {
  command zsh "$PP_CONFIG_FILE:h/../bin/ppicker" doctor
}
p_config() {
  command zsh "$PP_CONFIG_FILE:h/../bin/ppicker" init
}

# Core Actions
_pp_open() {
  local action="$1" editor="$2" sel="$3"
  case "$action" in
    cd)     [[ -d "$sel" ]] && builtin cd "$sel" || builtin cd "$(dirname "$sel")" ;;
    custom) _pp_run_editor "$editor" "$sel" ;;
    *)      _pp_run_editor "$editor" "$sel" ;;
  esac
}

# Command: p (prompt)
p() {
  emulate -L zsh
  setopt localoptions no_auto_name_dirs
  unsetopt xtrace verbose

  _pp_quiet_push
  _pp_require
  _pp_load_toml
  local -a keys; keys=("${(@k)PP_SCOPE_PATHS}")
  _pp_quiet_pop
  (( ${#keys[@]} )) || { _pp_die "no scopes configured"; return 1; }

  # Handle subcommands/help BEFORE getopts so --help is not eaten
  case "$1" in
    help|--help|-h) _pp_help; return ;;
    reload)         p_reload; return ;;
    doctor)         p_doctor; return ;;
    config)         p_config; return ;;
  esac

  local action="open" editor="" key="" OPTIND opt
  OPTERR=0
  while getopts "te:" opt; do
    case "$opt" in
      t) action="cd" ;;
      e) editor="$OPTARG" ;;
      \?) ;;  # ignore unknown short opts
    esac
  done
  shift $((OPTIND-1))

  # Ensure cache dir + log file exist (prevents grep error in preview)
  _pp_bootstrap_fs

  print -r -- "Scopes: ${keys[*]}  (or 'all')"
  printf "Choose scope key (default 'all'): "
  read -r key
  [[ -z "$key" ]] && key="all"

  local cache sel chosen_key label chosen_editor
  if [[ "$key" == "all" ]]; then
    _pp_quiet_push
    cache="$(_pp_build_cache_all)"
    local -a items; items=("${(@f)$(<"$cache")}")
    _pp_quiet_pop
    unset PP_PREVIEW_EDITOR
    sel="$(_pp_pick_from_list "${items[@]}")" || return
    chosen_key="$(_pp_key_for_path "$sel")"
  else
    [[ -n "${PP_SCOPE_PATHS[$key]}" ]] || { _pp_die "unknown scope key: $key"; return 1; }
    _pp_quiet_push
    cache="$(_pp_build_cache_for_key "$key")"
    local -a items; items=("${(@f)$(<"$cache")}")
    _pp_quiet_pop
    export PP_PREVIEW_EDITOR="${editor:-${PP_SCOPE_EDITORS[$key]:-$PP_DEFAULT_EDITOR}}"
    sel="$(_pp_pick_from_list "${items[@]}")" || { unset PP_PREVIEW_EDITOR; return; }
    unset PP_PREVIEW_EDITOR
    chosen_key="$key"
  fi

  [[ -z "$sel" ]] && return
  [[ -z "$chosen_key" ]] && chosen_key="$(_pp_key_for_path "$sel")"

  label="${PP_SCOPE_LABELS[$chosen_key]:-$chosen_key}"
  chosen_editor="${editor:-${PP_SCOPE_EDITORS[$chosen_key]:-$PP_DEFAULT_EDITOR}}"

  _pp_quiet_push
  print -r -- "$sel" >| "$(_pp_last "$chosen_key")"
  _pp_log "$label" "${action:-open}" "$sel"
  _pp_quiet_pop

  _pp_announce "$label" "${action:-open}" "$chosen_editor" "$sel"
  if [[ "$action" == "cd" ]]; then _pp_open cd "" "$sel"; else _pp_open open "$chosen_editor" "$sel"; fi
}
 

# Generate p<key> / p<key>l per scope
_pp_define_scope_cmds() {
  local k fn
  # Remove previously generated scope functions to avoid stale commands
  if [[ -n ${PP_DEFINED_SCOPE_CMDS:+x} ]]; then
    for k in "${PP_DEFINED_SCOPE_CMDS[@]}"; do
      for fn in p$k p${k}l; do
        whence -w "$fn" >/dev/null 2>&1 && unfunction "$fn" 2>/dev/null || true
      done
    done
  fi
  PP_DEFINED_SCOPE_CMDS=()
  for k in "${(@k)PP_SCOPE_PATHS}"; do
    PP_DEFINED_SCOPE_CMDS+=("$k")
    eval "
p$k() {
  emulate -L zsh
  setopt localoptions noshwordsplit pipefail no_auto_name_dirs
  unsetopt xtrace verbose
  _pp_quiet_push
  _pp_require
  _pp_load_toml
  local action=\"open\" editor=\"\" OPTIND opt
  OPTERR=0
  while getopts \"te:\" opt; do case \"\$opt\" in t) action=\"cd\";; e) editor=\"\$OPTARG\";; \\?) ;; esac; done
  shift \$((OPTIND-1))
  _pp_bootstrap_fs
  local cache=\"\$(_pp_build_cache_for_key $k)\"
  local -a items; items=(\"\${(@f)\$(<\"\$cache\")}\")
  _pp_quiet_pop
  export PP_PREVIEW_EDITOR=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  local sel; sel=\"\$(_pp_pick_from_list \"\${items[@]}\")\" || { unset PP_PREVIEW_EDITOR; return; }
  unset PP_PREVIEW_EDITOR
  [[ -z \"\$sel\" ]] && return
  local label=\"\${PP_SCOPE_LABELS[$k]:-$k}\"
  local chosen_editor=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  _pp_quiet_push
  print -r -- \"\$sel\" >| \"\$(_pp_last $k)\"
  _pp_log \"\$label\" \"\${action:-open}\" \"\$sel\"
  _pp_quiet_pop
  _pp_announce \"\$label\" \"\${action:-open}\" \"\$chosen_editor\" \"\$sel\"
  if [[ \"\$action\" == \"cd\" ]]; then _pp_open cd \"\" \"\$sel\"; else _pp_open open \"\$chosen_editor\" \"\$sel\"; fi
}
p${k}l() {
  emulate -L zsh
  setopt localoptions noshwordsplit pipefail no_auto_name_dirs
  unsetopt xtrace verbose
  _pp_quiet_push
  _pp_require
  _pp_load_toml
  local action=\"open\" editor=\"\" OPTIND opt
  OPTERR=0
  while getopts \"te:\" opt; do case \"\$opt\" in t) action=\"cd\";; e) editor=\"\$OPTARG\";; \\?) ;; esac; done
  shift \$((OPTIND-1))
  _pp_bootstrap_fs
  local f=\"\$(_pp_last $k)\"
  _pp_quiet_pop
  [[ -s \"\$f\" ]] || { _pp_warn \"No last \${PP_SCOPE_LABELS[$k]:-$k} project yet.\"; return 1; }
  local sel; sel=\"\$(<\"\$f\")\"
  local label=\"\${PP_SCOPE_LABELS[$k]:-$k}\"
  local chosen_editor=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  _pp_quiet_push
  _pp_log \"\$label\" \"\${action:-open}\" \"\$sel\"
  _pp_quiet_pop
  _pp_announce \"\$label\" \"\${action:-open}\" \"\$chosen_editor\" \"\$sel\"
  if [[ \"\$action\" == \"cd\" ]]; then _pp_open cd \"\" \"\$sel\"; else _pp_open open \"\$chosen_editor\" \"\$sel\"; fi
}
"
  done
}

# Initialization
_pp_load_toml
_pp_define_scope_cmds