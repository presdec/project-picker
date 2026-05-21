# project-picker.plugin.zsh

# Defaults & Globals
unsetopt xtrace 2>/dev/null || true
unsetopt verbose 2>/dev/null || true
set +x +v 2>/dev/null || true

# Capture plugin directory at source time (works with oh-my-zsh, prezto, zinit, manual source)
typeset -g __PP_PLUGIN_DIR="${${(%):-%x}:A:h}"

# Add completions dir to fpath so _ppicker and _p are found without manual setup
if [[ -d "${__PP_PLUGIN_DIR}/completions" ]] && (( ! ${fpath[(I)${__PP_PLUGIN_DIR}/completions]} )); then
  fpath=("${__PP_PLUGIN_DIR}/completions" $fpath)
fi

typeset -g PP_CACHE_TTL_MIN=10
typeset -g PP_DEFAULT_EDITOR=code
typeset -g PP_PREVIEW=tree
typeset -g PP_DEPTH=1
typeset -g PP_EXCLUDES="node_modules:.git"
typeset -g PP_INCLUDE_WORKSPACES=true
typeset -g PP_CACHE_DIR="${PP_CACHE_DIR:-$HOME/.cache/project-picker}"
typeset -g PP_LOG_FILE="${PP_LOG_FILE:-${PP_CACHE_DIR}/history.log}"
typeset -g PP_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/project-picker/config.toml"
typeset -g PP_HISTORY_MAX_LINES=1000
typeset -ga PP_DEFINED_SCOPE_CMDS

# --- helpers, colors, and preview shell ---
# Colors for announcements (safe defaults if terminal doesn’t support)
typeset -g PP_CLR_RESET=$'\e[0m'
typeset -g PP_CLR_DIM=$'\e[2m'
typeset -g PP_CLR_BOLD=$'\e[1m'
typeset -g PP_CLR_GREEN=$'\e[32m'
typeset -g PP_CLR_BLUE=$'\e[34m'

_pp_warn() { print -r -- "project-picker: $*" >&2; }
_pp_die()  { print -r -- "project-picker: error: $*" >&2; }
_pp_dbg()  { [[ -n "${PP_DEBUG:-}" ]] && print -r -- "[pp_debug $(date +%T)] $*" >> /tmp/pp_debug.log; }

# Shell used for fzf preview scripts (keep minimal and universal)
typeset -g PP_PREVIEW_SHELL="${PP_PREVIEW_SHELL:-/bin/sh}"

# Quiet helpers: temporarily silence stdout/stderr with a stack
typeset -ga __PP_QSTACK_OUT=() __PP_QSTACK_ERR=()
_pp_quiet_push() {
  local o e
  exec {o}>&1 {e}>&2
  __PP_QSTACK_OUT+=("$o")
  __PP_QSTACK_ERR+=("$e")
  exec >/dev/null 2>&1
}
_pp_quiet_pop() {
  local o e
  (( ${#__PP_QSTACK_OUT[@]} )) || return 0
  o=${__PP_QSTACK_OUT[-1]}
  e=${__PP_QSTACK_ERR[-1]}
  __PP_QSTACK_OUT[-1]=()
  __PP_QSTACK_ERR[-1]=()
  [[ -n "$o" && -n "$e" ]] || return 1
  exec 1>&$o 2>&$e
  exec {o}>&- {e}>&-
}
_pp_quiet_restore_to() {
  local target="${1:-0}"
  while (( ${#__PP_QSTACK_OUT[@]} > target )); do
    _pp_quiet_pop || break
  done
}

_pp_have() { command -v "$1" >/dev/null 2>&1; }
_pp_fd_cmd() {
  if _pp_have fd; then
    print -r -- "fd"
  elif _pp_have fdfind; then
    print -r -- "fdfind"
  else
    return 1
  fi
}
_pp_expand_tilde() { [[ "$1" == ~* ]] && echo ${~1} || echo "$1"; }
_pp_join_colon() { local IFS=:; print -r -- "$*"; }

_pp_bootstrap_fs() {
  mkdir -p "$PP_CACHE_DIR" 2>/dev/null || true
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
_pp_config_newer_than_cache() {
  local cache="$1"
  [[ ! -f "$PP_CONFIG_FILE" || ! -f "$cache" ]] && return 1
  local cfg_mt cache_mt
  cfg_mt="$(_pp_file_mtime_epoch "$PP_CONFIG_FILE")"
  cache_mt="$(_pp_file_mtime_epoch "$cache")"
  (( cfg_mt > cache_mt ))
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
  _pp_fd_cmd >/dev/null || missing+=("fd/fdfind")
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
  cur_lines=$(wc -l < "$PP_LOG_FILE" 2>/dev/null | tr -d ' \t')
  if [[ -n "$cur_lines" && "$cur_lines" -gt "$max_lines" ]]; then
    tail -n "$max_lines" "$PP_LOG_FILE" > "$PP_LOG_FILE.tmp" && mv "$PP_LOG_FILE.tmp" "$PP_LOG_FILE"
  fi
}
ph()  { command tail -n "${1:-50}" "$PP_LOG_FILE" 2>/dev/null | sed 's/\t/  |  /g'; }
phg() { command grep -i -- "$1" "$PP_LOG_FILE" 2>/dev/null | sed 's/\t/  |  /g'; }
phc() { : >| "$PP_LOG_FILE"; echo "history cleared: $PP_LOG_FILE"; }

# TOML Helpers
_pp_strip_toml_comment() {
  local line="$1" result="" char
  local -i in_quote=0 i=0 n=${#line}
  while (( i < n )); do
    char="${line:$i:1}"
    if (( in_quote )); then
      if [[ "$char" == '\' ]] && (( i + 1 < n )) && [[ "${line:$((i+1)):1}" == '"' ]]; then
        result+='\"'; (( i += 2 )); continue
      fi
      [[ "$char" == '"' ]] && in_quote=0
      result+="$char"
    else
      if [[ "$char" == '"' ]]; then in_quote=1; result+="$char"
      elif [[ "$char" == '#' ]]; then break
      else result+="$char"
      fi
    fi
    (( i++ ))
  done
  print -r -- "$result"
}

_pp_parse_toml_array() {
  local raw="$1" current="" char
  local -i in_dq=0 in_sq=0 i=0 n=${#raw}
  while (( i < n )); do
    char="${raw:$i:1}"
    if (( in_dq )); then
      if [[ "$char" == '\' ]] && (( i + 1 < n )) && [[ "${raw:$((i+1)):1}" == '"' ]]; then
        current+='"'; (( i += 2 )); continue
      fi
      if [[ "$char" == '"' ]]; then in_dq=0; else current+="$char"; fi
    elif (( in_sq )); then
      if [[ "$char" == "'" ]]; then in_sq=0; else current+="$char"; fi
    else
      if [[ "$char" == '"' ]]; then in_dq=1
      elif [[ "$char" == "'" ]]; then in_sq=1
      elif [[ "$char" == ',' ]]; then
        local _t="${current## }"; _t="${_t%% }"
        [[ -n "$_t" ]] && print -r -- "$_t"
        current=""
      else current+="$char"
      fi
    fi
    (( i++ ))
  done
  local _t="${current## }"; _t="${_t%% }"
  [[ -n "$_t" ]] && print -r -- "$_t"
}

_pp_unquote_toml() {
  local v="$1"
  v="${v## }"; v="${v%% }"
  if [[ "$v" == '"'*'"' ]]; then
    v="${v#\"}"; v="${v%\"}"; v="${v//\\\"/\"}"
  elif [[ "$v" == "'"*"'" ]]; then
    v="${v#\'}"; v="${v%\'}"
  fi
  print -r -- "$v"
}

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
    line="$(_pp_strip_toml_comment "$line")"
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
          default_editor)       PP_DEFAULT_EDITOR="$(_pp_unquote_toml "$v")" ;;
          preview)              PP_PREVIEW="$(_pp_unquote_toml "$v")" ;;
          depth)                PP_DEPTH="${v//[[:space:]]/}" ;;
          include_workspaces)   PP_INCLUDE_WORKSPACES="${v//[[:space:]]/}" ;;
          excludes)
            raw="${v#\[}"; raw="${raw%\]}"
            local -a _gexcl=()
            while IFS= read -r _tok; do [[ -n "$_tok" ]] && _gexcl+=("$_tok"); done < <(_pp_parse_toml_array "$raw")
            PP_EXCLUDES="${(j.:.)_gexcl}"
            ;;
        esac
        continue
      fi
      if [[ "$section" == scopes.* ]]; then
        local skey="${section#scopes.}"
        skey="${skey//[^a-zA-Z0-9]/}"
        skey="${skey:l}"
        [[ -z "$skey" ]] && continue
        case "$k" in
          label)   PP_SCOPE_LABELS[$skey]="$(_pp_unquote_toml "$v")" ;;
          editor)  PP_SCOPE_EDITORS[$skey]="$(_pp_unquote_toml "$v")" ;;
          depth)   PP_SCOPE_DEPTH[$skey]="${v//[[:space:]]/}" ;;
          include_workspaces) PP_SCOPE_INCLUDE_WS[$skey]="${v//[[:space:]]/}" ;;
          excludes)
            raw="${v#\[}"; raw="${raw%\]}"
            local -a _sexcl=()
            while IFS= read -r _tok; do [[ -n "$_tok" ]] && _sexcl+=("$_tok"); done < <(_pp_parse_toml_array "$raw")
            PP_SCOPE_EXCLUDES[$skey]="${(j.:.)_sexcl}"
            ;;
          paths)
            raw="${v#\[}"; raw="${raw%\]}"
            local -a parts=() expanded=()
            while IFS= read -r _tok; do [[ -n "$_tok" ]] && parts+=("$_tok"); done < <(_pp_parse_toml_array "$raw")
            for _tok in "${parts[@]}"; do
              expanded+=("$(_pp_expand_tilde "$_tok")")
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
  local X="$1" x
  for x in ${(s.:.)X}; do
    [[ -n "$x" ]] && reply+=( -E "$x" )
  done
}
_pp_exclude_args_find_array() {
  reply=()
  local X="$1" x
  for x in ${(s.:.)X}; do
  [[ -n "$x" ]] && reply+=( ! -path "*/$x/*" )
  done
}

_pp_list_projects_one_root() {
  emulate -L zsh
  setopt localoptions noshwordsplit noglobsubst
  local root="$1" depth="$2" include_ws="$3" excludes="$4"
  local fd_bin
  if fd_bin="$(_pp_fd_cmd)"; then
    local -a ex; _pp_exclude_args_fd_array "$excludes"; ex=("${reply[@]}")
    command "$fd_bin" -a -t d -d "$depth" . "$root" "${ex[@]}"
    if [[ "$include_ws" == "true" || "$include_ws" == "1" ]]; then
      command "$fd_bin" -a -t f -d "$depth" --extension code-workspace . "$root" "${ex[@]}"
    fi
  else
    local root_clean="$root"
    [[ "$root_clean" == */ ]] && root_clean="${root_clean%/}"
    local -a prune_expr
    local x
    for x in ${(s.:.)excludes}; do
      [[ -n "$x" ]] && prune_expr+=( -name "$x" -o )
    done
    (( ${#prune_expr[@]} )) && prune_expr[-1]=()

    if command find "$root_clean" -maxdepth 0 -type d >/dev/null 2>&1; then
      if (( ${#prune_expr[@]} )); then
        command find "$root_clean" -maxdepth "$depth" \( "${prune_expr[@]}" \) -prune -o -type d -print
      else
        command find "$root_clean" -maxdepth "$depth" -type d -print
      fi
      if [[ "$include_ws" == "true" || "$include_ws" == "1" ]]; then
        if (( ${#prune_expr[@]} )); then
          command find "$root_clean" -maxdepth "$depth" \( "${prune_expr[@]}" \) -prune -o -type f -name '*.code-workspace' -print
        else
          command find "$root_clean" -maxdepth "$depth" -type f -name '*.code-workspace' -print
        fi
      fi
      return
    fi

    # Portable fallback when find lacks -maxdepth: prune excluded names, then
    # filter by slash count.
    local base_slashes
    base_slashes=$(printf '%s' "$root_clean" | awk -F/ '{print NF-1}')
    local max_slashes=$(( base_slashes + depth ))
    if (( ${#prune_expr[@]} )); then
      command find "$root_clean" \( "${prune_expr[@]}" \) -prune -o -type d -print \
        | awk -v md="$max_slashes" '{n=gsub(/\//,"&"); if (n<=md) print $0}'
    else
      command find "$root_clean" -type d -print \
        | awk -v md="$max_slashes" '{n=gsub(/\//,"&"); if (n<=md) print $0}'
    fi
    if [[ "$include_ws" == "true" || "$include_ws" == "1" ]]; then
      if (( ${#prune_expr[@]} )); then
        command find "$root_clean" \( "${prune_expr[@]}" \) -prune -o -type f -name '*.code-workspace' -print \
          | awk -v md="$max_slashes" '{n=gsub(/\//,"&"); if (n<=md) print $0}'
      else
        command find "$root_clean" -type f -name '*.code-workspace' -print \
          | awk -v md="$max_slashes" '{n=gsub(/\//,"&"); if (n<=md) print $0}'
      fi
    fi
  fi
}

_pp_build_cache_for_key() {
  local key="$1"
  # Ensure cache dir and log file exist before writing
  _pp_bootstrap_fs
  local cache="$(_pp_cache "$key")"
  local depth="${PP_SCOPE_DEPTH[$key]:-$PP_DEPTH}"
  local incws="${PP_SCOPE_INCLUDE_WS[$key]:-$PP_INCLUDE_WORKSPACES}"
  local excludes
  if (( ${+PP_SCOPE_EXCLUDES[$key]} )); then
    excludes="${PP_SCOPE_EXCLUDES[$key]}"
  else
    excludes="$PP_EXCLUDES"
  fi

  if _pp_is_cache_stale "$cache" "$PP_CACHE_TTL_MIN" || _pp_config_newer_than_cache "$cache"; then
    : >| "$cache"
    local paths="${PP_SCOPE_PATHS[$key]}"
    local r
    for r in ${(s.:.)paths}; do
      [[ -d "$r" ]] || continue
      _pp_list_projects_one_root "$r" "$depth" "$incws" "$excludes" >> "$cache"
    done
  fi
  echo "$cache"
}

_pp_build_cache_all() {
  # Ensure cache dir and log file exist before writing
  _pp_bootstrap_fs
  local cache="$(_pp_cache all)"
  if _pp_is_cache_stale "$cache" "$PP_CACHE_TTL_MIN" || _pp_config_newer_than_cache "$cache"; then
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
  _pp_dbg "_pp_pick_from_list called with ${#src[@]} items"
  (( ${#src[@]} )) || { _pp_dbg "EARLY RETURN: no items"; return 1; }

  local -a lines labels paths
  local it p leaf safe_it i=1
  for it in "${src[@]}"; do
    # Only accept absolute paths to avoid stray lines (e.g., headers) entering the list
    [[ "$it" == /* ]] || continue
    p="${it%/}"
    leaf="${p:t}"
    [[ "$leaf" == *.code-workspace ]] && leaf="${leaf%.code-workspace}"
    leaf="${leaf//$'\t'/ }"      # guard tabs in label
    safe_it="${p//$'\t'/ }"      # guard tabs in path
    # columns: 1=index 2=label (shown) 3=path (result)
    lines+=("$i"$'\t'"$leaf"$'\t'"$safe_it")
    labels+=("$leaf")
    paths+=("$safe_it")
    ((i++))
  done

  _pp_dbg "items passed filter: labels=${#labels[@]} paths=${#paths[@]}"
  if _pp_have fzf; then
    _pp_dbg "fzf FOUND — using fzf branch (TUI will NOT run)"
    local selected
    local pprompt="Project >"
    [[ -n "$PP_PICKER_HEADER" ]] && pprompt="Project $PP_PICKER_HEADER > "
    # Optional: allow non-interactive filtering (e.g., in CI) via PP_FZF_FILTER
    local -a fzf_extra
    if [[ -n "$PP_FZF_FILTER" ]]; then
      fzf_extra=( --filter "$PP_FZF_FILTER" )
    else
      fzf_extra=()
    fi
    if [[ "$PP_PREVIEW" == "tree" && $(_pp_have tree; echo $?) -eq 0 ]]; then
      selected=$(printf '%s\n' "${lines[@]}" \
        | command env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -- fzf \
          --no-multi --ansi --delimiter $'\t' --with-nth=2 \
          --prompt="$pprompt" --height=80% --layout=reverse --border "${fzf_extra[@]}" \
          --preview-window=right,60%,wrap,border \
          --delimiter '\t' --with-nth=2 \
          --preview '
            p={3}
            if [ -z "$p" ]; then
              echo "(no path)"; exit 0
            fi
            if [ -d "$p" ]; then
              if command -v tree >/dev/null 2>&1; then
                tree -a -L 2 "$p"
              else
                echo "(tree missing: showing ls)"
                ls -A "$p" | sed -n "1,80p"
              fi
            elif [ -f "$p" ]; then
              head -n 120 "$p"
            else
              echo "(path not found) $p"
            fi
            '
      ) || return 1
    else
      selected=$(printf '%s\n' "${lines[@]}" \
        | command env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -- fzf \
          --no-multi --ansi --delimiter $'\t' --with-nth=2 \
          --prompt="$pprompt" --height=80% --layout=reverse --border "${fzf_extra[@]}" \
          --preview-window=right,60%,wrap,border \
          --delimiter '\t' --with-nth=2 \
          --preview '
          p={3}
          if [ -z "$p" ]; then
            echo "(no path)"; exit 0
          fi
          if [ -d "$p" ]; then
            if command -v tree >/dev/null 2>&1; then
              tree -a -L 2 "$p"
            else
              echo "(tree missing: showing ls)"
              ls -A "$p" | sed -n "1,80p"
            fi
          elif [ -f "$p" ]; then
            head -n 120 "$p"
          else
            echo "(path not found) $p"
          fi
          '
      ) || return 1
    fi
    # If non-interactive filtering was used, pick only the first match
    if [[ -n "$PP_FZF_FILTER" ]]; then
      local -a _pp_sel_lines
      _pp_sel_lines=(${(f)selected})
      selected="${_pp_sel_lines[1]}"
    fi
    printf '%s\n' "$selected" | cut -d $'\t' -f3-
  else
    # Minimal interactive filter when fzf is unavailable. Write UI to /dev/tty
    # because this function is usually called inside command substitution.
    local -a fi_labels fi_paths
    integer i
    for (( i=1; i<=${#labels[@]}; i++ )); do
      fi_labels+=("${labels[$i]}")
      fi_paths+=("${paths[$i]}")
    done
    _pp_dbg "fzf NOT found — entering pure-zsh TUI (fi_labels=${#fi_labels[@]})"
    local _tui_in=0 _tui_out=2 _tui_has_tty=0
    if { : </dev/tty; } 2>/dev/null && { : >/dev/tty; } 2>/dev/null &&
       exec {_tui_in}</dev/tty && exec {_tui_out}>/dev/tty; then
      _tui_has_tty=1
    fi

    if (( _tui_has_tty )); then
      local -a _vl _vp
      local _q="" _sel=0 _scroll=0 _key _seq _k2 _result="" _done=0
      local _th _tw _lh _mw _end _i _r _lbl _ql _j _vc _drawn _pv _ppath _pline _frame
      local _stty_state
      _stty_state=$(command stty -g <&$_tui_in 2>/dev/null || true)

      {
        command stty -echo -icanon min 1 time 0 <&$_tui_in 2>/dev/null || true
        printf '\e[?1049h\e[?25l\e[2J\e[H' >&$_tui_out

        while (( ! _done )); do
          _vl=()
          _vp=()
          if [[ -n "$_q" ]]; then
            _ql="${_q:l}"
            for (( _j=1; _j<=${#fi_labels[@]}; _j++ )); do
              if [[ "${fi_labels[$_j]:l}" == *${_ql}* ]]; then
                _vl+=("${fi_labels[$_j]}")
                _vp+=("${fi_paths[$_j]}")
              fi
            done
          else
            _vl=("${fi_labels[@]}")
            _vp=("${fi_paths[@]}")
          fi

          _vc=${#_vl[@]}
          (( _sel >= _vc && _vc > 0 )) && _sel=$(( _vc - 1 ))
          (( _sel < 0 )) && _sel=0
          _th=$(tput lines 2>/dev/null || echo 24)
          _tw=$(tput cols 2>/dev/null || echo 80)
          # Keep at least one spare row at the bottom. Printing on the last
          # terminal row can scroll the frame and hide the header.
          _lh=$(( _th - 11 ))
          (( _lh < 3 )) && _lh=3
          (( _scroll > _sel )) && _scroll=$_sel
          (( _sel >= _scroll + _lh )) && _scroll=$(( _sel - _lh + 1 ))
          _mw=$(( _tw - 5 ))

          _frame=$'\e[H'
          _frame+=$'\r\e[K'
          _frame+="  "$'\e[1m'"${PP_PICKER_HEADER:-Projects}"$'\e[0m'
          _frame+="  "$'\e[2m'"up/down navigate | type filter | enter select | q quit"$'\e[0m'$'\n'
          _frame+=$'\r\e[K'"  > "$'\e[4m'"$_q "$'\e[0m'$'\n'
          _frame+=$'\r\e[K'$'\n'

          _end=$(( _scroll + _lh ))
          (( _end > _vc )) && _end=$_vc
          for (( _i=_scroll; _i<_end; _i++ )); do
            _lbl="${_vl[$(( _i + 1 ))]}"
            (( ${#_lbl} > _mw )) && _lbl="${_lbl[1,$_mw]}"
            if (( _i == _sel )); then
              _frame+="$(printf '\r\e[K  \e[7m %-*s \e[0m' "$_mw" "$_lbl")"$'\n'
            else
              _frame+="$(printf '\r\e[K   %-*s' "$_mw" "$_lbl")"$'\n'
            fi
          done
          (( _vc == 0 )) && _frame+=$'\r\e[K  \e[2m(no matches)\e[0m\n'

          _drawn=$(( _end - _scroll ))
          (( _vc == 0 )) && _drawn=1
          for (( _r=_drawn; _r<_lh; _r++ )); do _frame+=$'\r\e[K'$'\n'; done

          _frame+="$(printf '\r\e[K  \e[2m%s\e[0m' "${(l:$(( _tw - 2 ))::-:)}")"$'\n'
          _pv=0
          if (( _vc > 0 )); then
            _ppath="${_vp[$(( _sel + 1 ))]}"
            _frame+="$(printf '\r\e[K  \e[2m%s\e[0m' "$_ppath")"$'\n'
            (( _pv++ ))
            if [[ -d "$_ppath" ]]; then
              while IFS= read -r _pline && (( _pv < 5 )); do
                _frame+="$(printf '\r\e[K    \e[2m%s\e[0m' "$_pline")"$'\n'
                (( _pv++ ))
              done < <(command ls -1 "$_ppath" 2>/dev/null)
            fi
          fi
          for (( _r=_pv; _r<5; _r++ )); do _frame+=$'\r\e[K'$'\n'; done
          printf '%s' "$_frame" >&$_tui_out

          if ! IFS= read -r -k 1 _key <&$_tui_in; then
            _done=1
            break
          fi
          case "$_key" in
            $'\003') _done=1 ;;
            q)
              if [[ -n "$_q" ]]; then
                _q+="$_key"
                _sel=0
                _scroll=0
              else
                _done=1
              fi
              ;;
            $'\r'|$'\n')
              (( _vc > 0 )) && _result="${_vp[$(( _sel + 1 ))]}"
              _done=2
              ;;
            $'\177'|$'\010')
              [[ -n "$_q" ]] && { _q="${_q%?}"; _sel=0; _scroll=0; }
              ;;
            $'\e')
              _seq=""
              if IFS= read -r -t 0.05 -k 1 _k2 <&$_tui_in 2>/dev/null; then
                _seq="$_k2"
                if IFS= read -r -t 0.05 -k 1 _k2 <&$_tui_in 2>/dev/null; then
                  _seq+="$_k2"
                fi
              fi
              case "$_seq" in
                '[A') (( _sel > 0 )) && (( _sel-- )) ;;
                '[B') (( _vc > 0 && _sel < _vc - 1 )) && (( _sel++ )) ;;
                '') _done=1 ;;
              esac
              ;;
            *)
              if [[ -n "$_key" && "$_key" != [$'\000'-$'\037'] ]]; then
                _q+="$_key"
                _sel=0
                _scroll=0
              fi
              ;;
          esac
        done
      } always {
        [[ -n "$_stty_state" ]] && command stty "$_stty_state" <&$_tui_in 2>/dev/null || true
        printf '\e[?25h\e[?1049l' >&$_tui_out
        exec {_tui_in}<&-
        exec {_tui_out}>&-
      }

      [[ -n "$_result" ]] && { print -r -- "$_result"; return 0; }
      return 1
    fi

    local ans q ql idx n pp
    while true; do
      printf '\n' >&$_tui_out
      [[ -n "$PP_PICKER_HEADER" ]] && printf '%s\n' "$PP_PICKER_HEADER" >&$_tui_out
      idx=1
      for leaf in "${fi_labels[@]}"; do
        printf '%2d) %s\n' $idx "$leaf" >&$_tui_out
        ((idx++))
      done
      printf 'Select number, /text to filter, or q: ' >&$_tui_out
      if ! IFS= read -r ans <&$_tui_in; then
        (( _tui_has_tty )) && { exec {_tui_in}<&-; exec {_tui_out}>&-; }
        return 1
      fi
      [[ "$ans" == q ]] && { (( _tui_has_tty )) && { exec {_tui_in}<&-; exec {_tui_out}>&-; }; return 1; }
      if [[ "$ans" == /* ]]; then
        q="${ans#/}"
        ql="${q:l}"
        fi_labels=()
        fi_paths=()
        for (( i=1; i<=${#labels[@]}; i++ )); do
          leaf="${labels[$i]}"
          pp="${paths[$i]}"
          if [[ "${leaf:l}" == *${ql}* ]]; then
            fi_labels+=("$leaf")
            fi_paths+=("$pp")
          fi
        done
        (( ${#fi_labels[@]} )) || printf '(no matches)\n' >&$_tui_out
        continue
      fi
      if [[ -n "$ans" && "$ans" == <-> ]]; then
        n=$ans
        if (( n >= 1 && n <= ${#fi_paths[@]} )); then
          print -r -- "${fi_paths[$n]}"
          (( _tui_has_tty )) && { exec {_tui_in}<&-; exec {_tui_out}>&-; }
          return 0
        fi
      fi
      printf 'Invalid input.\n' >&$_tui_out
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
  print -r -- "  p --config              Run config wizard (interactive setup)"
  print -r -- "  p --doctor              Validate config and dependencies"
  print -r -- "  p --reload              Reload config and regenerate plugin functions"
  print -r -- "Options:"
  print -r -- "  -d                      cd into project instead of opening"
  print -r -- "  -e <editor>             Override editor (code|idea|cursor|windsurf|nvim|vim|codium|custom:/path)"
  print -r -- "  --config                Run config wizard"
  print -r -- "  --doctor                Validate config and dependencies"
  print -r -- "  --reload                Reload config and regenerate plugin functions"
  print -r -- "  --help                  Show this help"
  print -r -- "Config: ${PP_CONFIG_FILE}"
}

_pp_parse_picker_args() {
  local __action_var="$1" __editor_var="$2"
  shift 2
  local action="open" editor=""
  while (( $# )); do
    case "$1" in
      -d)
        action="cd"
        shift
        ;;
      -e)
        local opt_name="$1"
        shift
        if (( ! $# )); then
          _pp_die "missing editor for $opt_name"
          return 2
        fi
        editor="$1"
        shift
        ;;
      --help|-h)
        _pp_help
        return 10
        ;;
      --)
        shift
        break
        ;;
      -*)
        _pp_die "unknown option: $1"
        return 2
        ;;
      *)
        break
        ;;
    esac
  done
  typeset -g __PP_PARSED_ACTION="$action"
  typeset -g __PP_PARSED_EDITOR="$editor"
  return 0
}

# Reloader and CLI bridge
p_reload() {
  local self="${__PP_PLUGIN_DIR}/project-picker.plugin.zsh"
  if [[ ! -r "$self" ]]; then
    _pp_warn "cannot find plugin file: $self"
    return 1
  fi
  { emulate -L zsh; setopt localoptions; unsetopt xtrace verbose; source "$self"; } >/dev/null 2>&1
  print -r -- "Project Picker plugin reloaded."
}
p_doctor() {
  command zsh "${__PP_PLUGIN_DIR}/bin/ppicker" doctor
}
p_config() {
  command zsh "${__PP_PLUGIN_DIR}/bin/ppicker" init
}

# Core Actions
_pp_open() {
  local action="$1" editor="$2" sel="$3"
  case "$action" in
    cd)
      local _cd_target
      if [[ -d "$sel" ]]; then
        _cd_target="$sel"
      else
        # For workspace files or non-directory selections, cd to parent
        _cd_target="${sel:h}"
      fi
      if [[ ! -d "$_cd_target" ]]; then
        _pp_warn "directory not found: $_cd_target"
        return 1
      fi
      builtin cd -- "$_cd_target" || { _pp_warn "cd failed: $_cd_target"; return 1; }
      ;;
    custom) _pp_run_editor "$editor" "$sel" ;;
    *)      _pp_run_editor "$editor" "$sel" ;;
  esac
}

# Command: p (prompt)
p() {
  emulate -L zsh
  setopt localoptions no_auto_name_dirs
  unsetopt xtrace verbose

  case "$1" in
    --help|-h|help)     _pp_help; return ;;
    --config|config|init) p_config; return ;;
    --doctor|doctor)   p_doctor; return ;;
    --reload|reload)   p_reload; return ;;
  esac

  local __pp_qd=${#__PP_QSTACK_OUT[@]}
  _pp_quiet_push
  {
    _pp_require
    _pp_load_toml
    local -a keys; keys=("${(@k)PP_SCOPE_PATHS}")
  } always {
    _pp_quiet_restore_to "$__pp_qd"
  }
  (( ${#keys[@]} )) || { _pp_die "no scopes configured"; return 1; }

  # Auto-setup when no config exists
  if [[ ! -f "$PP_CONFIG_FILE" ]]; then
    print -r -- "No config found at $PP_CONFIG_FILE. Starting setup wizard..."
    p_config
    return
  fi

  local action="open" editor="" key=""
  _pp_parse_picker_args action editor "$@"
  local _pp_parse_rc=$?
  (( _pp_parse_rc == 10 )) && return 0
  (( _pp_parse_rc == 0 )) || return $_pp_parse_rc
  action="$__PP_PARSED_ACTION"
  editor="$__PP_PARSED_EDITOR"

  # Ensure cache dir + log file exist (prevents grep error in preview)
  _pp_bootstrap_fs

  print -r -- "Scopes: ${keys[*]}  (or 'all')"
  printf "Choose scope key (default 'all'): "
  read -r key
  [[ -z "$key" ]] && key="all"

  local cache sel chosen_key label chosen_editor
  if [[ "$key" == "all" ]]; then
    __pp_qd=${#__PP_QSTACK_OUT[@]}
    _pp_quiet_push
    {
      cache="$(_pp_build_cache_all)"
      local -a items; items=("${(@f)$(<"$cache")}")
    } always {
      _pp_quiet_restore_to "$__pp_qd"
    }
    _pp_dbg "p(): all scope cache=$cache items=${#items[@]}"
    unset PP_PREVIEW_EDITOR
    PP_PICKER_HEADER="Scope: all"
    sel="$(_pp_pick_from_list "${items[@]}")" || return
    chosen_key="$(_pp_key_for_path "$sel")"
  else
    [[ -n "${PP_SCOPE_PATHS[$key]}" ]] || { _pp_die "unknown scope key: $key"; return 1; }
    __pp_qd=${#__PP_QSTACK_OUT[@]}
    _pp_quiet_push
    {
      cache="$(_pp_build_cache_for_key "$key")"
      local -a items; items=("${(@f)$(<"$cache")}")
    } always {
      _pp_quiet_restore_to "$__pp_qd"
    }
    _pp_dbg "p(): scope=$key cache=$cache items=${#items[@]}"
    export PP_PREVIEW_EDITOR="${editor:-${PP_SCOPE_EDITORS[$key]:-$PP_DEFAULT_EDITOR}}"
    PP_PICKER_HEADER="Scope: ${PP_SCOPE_LABELS[$key]:-$key}"
    sel="$(_pp_pick_from_list "${items[@]}")" || { unset PP_PREVIEW_EDITOR; return; }
    unset PP_PREVIEW_EDITOR
    chosen_key="$key"
  fi
  unset PP_PICKER_HEADER

  [[ -z "$sel" ]] && return
  [[ -z "$chosen_key" ]] && chosen_key="$(_pp_key_for_path "$sel")"

  label="${PP_SCOPE_LABELS[$chosen_key]:-$chosen_key}"
  chosen_editor="${editor:-${PP_SCOPE_EDITORS[$chosen_key]:-$PP_DEFAULT_EDITOR}}"

  __pp_qd=${#__PP_QSTACK_OUT[@]}
  _pp_quiet_push
  {
    print -r -- "$sel" >| "$(_pp_last "$chosen_key")"
    _pp_log "$label" "${action:-open}" "$sel"
  } always {
    _pp_quiet_restore_to "$__pp_qd"
  }

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
  local __pp_qd=\${#__PP_QSTACK_OUT[@]}
  _pp_quiet_push
  {
    _pp_require
    _pp_load_toml
  } always {
    _pp_quiet_restore_to \"\$__pp_qd\"
  }
  local action=\"open\" editor=\"\"
  _pp_parse_picker_args action editor \"\$@\"
  local _pp_parse_rc=\$?
  (( _pp_parse_rc == 10 )) && return 0
  (( _pp_parse_rc == 0 )) || return \$_pp_parse_rc
  action=\"\$__PP_PARSED_ACTION\"
  editor=\"\$__PP_PARSED_EDITOR\"
  _pp_bootstrap_fs
  __pp_qd=\${#__PP_QSTACK_OUT[@]}
  _pp_quiet_push
  {
    local cache=\"\$(_pp_build_cache_for_key $k)\"
    local -a items; items=(\"\${(@f)\$(<\"\$cache\")}\")
  } always {
    _pp_quiet_restore_to \"\$__pp_qd\"
  }
  export PP_PREVIEW_EDITOR=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  PP_PICKER_HEADER=\"Scope: \${PP_SCOPE_LABELS[$k]:-$k}\"
  local sel; sel=\"\$(_pp_pick_from_list \"\${items[@]}\")\" || { unset PP_PREVIEW_EDITOR PP_PICKER_HEADER; return; }
  unset PP_PREVIEW_EDITOR PP_PICKER_HEADER
  [[ -z \"\$sel\" ]] && return
  local label=\"\${PP_SCOPE_LABELS[$k]:-$k}\"
  local chosen_editor=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  __pp_qd=\${#__PP_QSTACK_OUT[@]}
  _pp_quiet_push
  {
    print -r -- \"\$sel\" >| \"\$(_pp_last $k)\"
    _pp_log \"\$label\" \"\${action:-open}\" \"\$sel\"
  } always {
    _pp_quiet_restore_to \"\$__pp_qd\"
  }
  _pp_announce \"\$label\" \"\${action:-open}\" \"\$chosen_editor\" \"\$sel\"
  if [[ \"\$action\" == \"cd\" ]]; then _pp_open cd \"\" \"\$sel\"; else _pp_open open \"\$chosen_editor\" \"\$sel\"; fi
}
p${k}l() {
  emulate -L zsh
  setopt localoptions noshwordsplit pipefail no_auto_name_dirs
  unsetopt xtrace verbose
  local __pp_qd=\${#__PP_QSTACK_OUT[@]}
  _pp_quiet_push
  {
    _pp_require
    _pp_load_toml
  } always {
    _pp_quiet_restore_to \"\$__pp_qd\"
  }
  local action=\"open\" editor=\"\"
  _pp_parse_picker_args action editor \"\$@\"
  local _pp_parse_rc=\$?
  (( _pp_parse_rc == 10 )) && return 0
  (( _pp_parse_rc == 0 )) || return \$_pp_parse_rc
  action=\"\$__PP_PARSED_ACTION\"
  editor=\"\$__PP_PARSED_EDITOR\"
  _pp_bootstrap_fs
  local f=\"\$(_pp_last $k)\"
  [[ -s \"\$f\" ]] || { _pp_warn \"No last \${PP_SCOPE_LABELS[$k]:-$k} project yet.\"; return 1; }
  local sel; sel=\"\$(<\"\$f\")\"
  local label=\"\${PP_SCOPE_LABELS[$k]:-$k}\"
  local chosen_editor=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  __pp_qd=\${#__PP_QSTACK_OUT[@]}
  _pp_quiet_push
  {
    _pp_log \"\$label\" \"\${action:-open}\" \"\$sel\"
  } always {
    _pp_quiet_restore_to \"\$__pp_qd\"
  }
  _pp_announce \"\$label\" \"\${action:-open}\" \"\$chosen_editor\" \"\$sel\"
  if [[ \"\$action\" == \"cd\" ]]; then _pp_open cd \"\" \"\$sel\"; else _pp_open open \"\$chosen_editor\" \"\$sel\"; fi
}
"
  done
}

# Initialization (silent)
__pp_init_qd=${#__PP_QSTACK_OUT[@]}
_pp_quiet_push
{
  _pp_load_toml
  _pp_define_scope_cmds
} always {
  _pp_quiet_restore_to "$__pp_init_qd"
  unset __pp_init_qd
}
