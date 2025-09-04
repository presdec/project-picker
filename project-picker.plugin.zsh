# --------------------------- ppicker Integration ----------------------------
# Run ppicker doctor from plugin
ppicker_doctor() {
  command zsh "$PP_CONFIG_FILE:h/../bin/ppicker" doctor
}
# Run ppicker init/config wizard from plugin
ppicker_config() {
  command zsh "$PP_CONFIG_FILE:h/../bin/ppicker" init
}
# project-picker.plugin.zsh
# Core Zsh plugin: TOML config → scopes → p/p<key>/p<key>l; fd/fzf/tree with fallbacks

# --------------------------- Defaults & Globals -------------------------------
typeset -g PP_CACHE_TTL_MIN=10
typeset -g PP_DEFAULT_EDITOR=code           # code|codium|idea|cursor|windsurf|nvim|vim|custom:/path/to/editor
typeset -g PP_PREVIEW=tree                  # tree|none
typeset -g PP_DEPTH=1
typeset -g PP_EXCLUDES="node_modules:.git"
typeset -g PP_INCLUDE_WORKSPACES=true
typeset -g PP_CACHE_DIR="${HOME}/.cache/project-picker"
typeset -g PP_LOG_FILE="${PP_CACHE_DIR}/history.log"
typeset -g PP_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/project-picker/config.toml"
mkdir -p "$PP_CACHE_DIR"

# Scopes (populated from TOML or default)
typeset -gA PP_SCOPE_PATHS      # key -> colon-delimited absolute dirs
typeset -gA PP_SCOPE_LABELS     # key -> label
typeset -gA PP_SCOPE_EDITORS    # key -> editor id
typeset -gA PP_SCOPE_DEPTH      # key -> depth (int)
typeset -gA PP_SCOPE_EXCLUDES   # key -> colon-delimited excludes
typeset -gA PP_SCOPE_INCLUDE_WS # key -> "true"/"false"

# --------------------------- Utilities & Fallbacks ---------------------------
_pp_have() { command -v "$1" >/dev/null 2>&1; }
_pp_warn() { print -r -- "project-picker: $*" >&2; }
_pp_die()  { _pp_warn "$*"; return 1; }

_pp_expand_tilde() {  # expand leading ~ and env vars; don't force existence
  local p="$1"
  # expand ~ and ${VAR}
  eval "print -r -- ${p:q}" 2>/dev/null
}

_pp_join_colon() { local IFS=:; print -r -- "$*"; }

# Colors & icons (ANSI + Nerd Fonts; fall back if font missing)
PP_CLR_RESET=$'\e[0m'; PP_CLR_DIM=$'\e[2m'; PP_CLR_BOLD=$'\e[1m'
PP_CLR_GREEN=$'\e[32m'; PP_CLR_BLUE=$'\e[34m'
_pp_icon_for() { case "$1" in cd) echo "";; custom) echo "";; *) echo "󰨞";; esac; }
_pp_label_for_action() { local a="$1" e="$2"; case "$a" in cd) echo cd;; custom) echo "${e:t:-editor}";; *) echo "VS Code";; esac; }
_pp_qpath() { local p="${1/#$HOME/~}"; printf '"%s"' "$p"; }
_pp_announce() {
  local scope="$1" action="$2" editor="$3" path="$4"
  local icon;  icon="$(_pp_icon_for "$action")"
  local label; label="$(_pp_label_for_action "$action" "$editor")"
  local pstr;  pstr="$(_pp_qpath "$path")"
  printf "${PP_CLR_GREEN}%s  Opened${PP_CLR_RESET} ${PP_CLR_BOLD}%s${PP_CLR_RESET} ${PP_CLR_DIM}with${PP_CLR_RESET} ${PP_CLR_BLUE}%s${PP_CLR_RESET} ${PP_CLR_DIM}(%s)${PP_CLR_RESET}\n" \
    "$icon" "$pstr" "$label" "$scope"
}

# Editor runners (VS Code/Codium clean NODE_OPTIONS)
_pp_run_editor() {
  local editor="$1" target="$2"
  case "$editor" in
    code)      (unset NODE_OPTIONS; command /usr/bin/code "$target") ;;
    codium)    (unset NODE_OPTIONS; command /usr/bin/codium "$target") ;;
    idea)      command idea "$target" ;;
    cursor)    command cursor "$target" ;;
    windsurf)  command windsurf "$target" ;;
    nvim)      command nvim "$target" ;;
    vim)       command vim "$target" ;;
    custom:*)  local cmd="${editor#custom:}"; command "$cmd" "$target" ;;
    *)         # fallback to default editor or VS Code
               if [[ "$PP_DEFAULT_EDITOR" == code ]]; then
                 (unset NODE_OPTIONS; command /usr/bin/code "$target")
               else
                 _pp_run_editor "$PP_DEFAULT_EDITOR" "$target"
               fi
               ;;
  esac
}

# Deps probe (non-fatal)
_pp_require() {
  local missing=()
  if ! _pp_have fd; then missing+=("fd"); fi
  if ! _pp_have fzf; then missing+=("fzf"); fi
  if [[ "$PP_PREVIEW" == "tree" && ! $(_pp_have tree; echo $?) -eq 0 ]]; then missing+=("tree"); fi
  (( ${#missing[@]} )) && _pp_warn "missing: ${missing[*]}  (falls back automatically)"
}

# Logging & history
_pp_cache() { echo "$PP_CACHE_DIR/projects.$1.list"; }     # key or 'all'
_pp_last()  { echo "$PP_CACHE_DIR/last.$1"; }              # key only
_pp_log() {
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf '%s\t%s\t%s\t%s\n' "$ts" "$1" "$2" "$3" >> "$PP_LOG_FILE"
}
ph()  { command tail -n "${1:-50}" "$PP_LOG_FILE" 2>/dev/null | sed 's/\t/  |  /g'; }
phg() { command grep -i -- "$1" "$PP_LOG_FILE" 2>/dev/null | sed 's/\t/  |  /g'; }
phc() { : >| "$PP_LOG_FILE"; echo "history cleared: $PP_LOG_FILE"; }

# ------------------------------- TOML Loader ---------------------------------
# Minimal parser for our schema only.
_pp_load_toml() {
  local cfg="$PP_CONFIG_FILE"
  if [[ ! -f "$cfg" ]]; then
    # Provide sane defaults if no config
    PP_SCOPE_PATHS=( [w]="$HOME/work" [p]="$HOME/mywork" )
    PP_SCOPE_LABELS=( [w]="work" [p]="personal" )
    PP_SCOPE_EDITORS=( [w]="$PP_DEFAULT_EDITOR" [p]="$PP_DEFAULT_EDITOR" )
    return 0
  fi

  local section="" key="" line k v arr raw
  while IFS= read -r line; do
    # strip comments
    line="${line%%#*}"
    # trim
    [[ -z "${line//[[:space:]]/}" ]] && continue
    # section header
    if [[ "$line" == \[*\] ]]; then
      section="${line#\[}"
      section="${section%\]}"
      continue
    fi

    # key = value
    if [[ "$line" == *"="* ]]; then
      k="${line%%=*}"; v="${line#*=}"
      k="${k//[[:space:]]/}"
      v="${v##[[:space:]]}"

      # Globals
      if [[ "$section" == "global" ]]; then
        case "$k" in
          cache_ttl_min)        PP_CACHE_TTL_MIN="${v//[[:space:]]/}";;
          default_editor)       PP_DEFAULT_EDITOR="${v//\"/}";;
          preview)              PP_PREVIEW="${v//\"/}";;
          depth)                PP_DEPTH="${v//[[:space:]]/}";;
          include_workspaces)   PP_INCLUDE_WORKSPACES="${v//[[:space:]]/}";;
          excludes)
            # array: [ "a", "b" ]
            raw="${v#\[}"; raw="${raw%\]}"
            raw="${raw//\"/}"; raw="${raw// /}"
            PP_EXCLUDES="${raw//,/":"}"
            ;;
        esac
        continue
      fi

      # Scopes: section "scopes.<key>"
      if [[ "$section" == scopes.* ]]; then
        local skey="${section#scopes.}"
        case "$k" in
          label)   PP_SCOPE_LABELS[$skey]="${v//\"/}";;
          editor)  PP_SCOPE_EDITORS[$skey]="${v//\"/}";;
          depth)   PP_SCOPE_DEPTH[$skey]="${v//[[:space:]]/}";;
          include_workspaces) PP_SCOPE_INCLUDE_WS[$skey]="${v//[[:space:]]/}";;
          excludes)
            raw="${v#\[}"; raw="${raw%\]}"
            raw="${raw//\"/}"; raw="${raw// /}"
            PP_SCOPE_EXCLUDES[$skey]="${raw//,/":"}"
            ;;
          paths)
            raw="${v#\[}"; raw="${raw%\]}"
            raw="${raw//\"/}"
            # split on comma, trim spaces, expand ~
            local -a parts=()
            IFS=',' read -A parts <<< "$raw"
            local -a expanded=()
            local p
            for p in "${parts[@]}"; do
              p="${p## }"; p="${p%% }"
              [[ -z "$p" ]] && continue
              expanded+=("$(_pp_expand_tilde "$p")")
            done
            PP_SCOPE_PATHS[$skey]="$(_pp_join_colon "${expanded[@]}")"
            ;;
        esac
        continue
      fi
    fi
  done < "$cfg"

  # Fallback labels/editors if missing
  local sk
  for sk in "${(@k)PP_SCOPE_PATHS}"; do
    [[ -n "${PP_SCOPE_LABELS[$sk]}" ]]  || PP_SCOPE_LABELS[$sk]="$sk"
    [[ -n "${PP_SCOPE_EDITORS[$sk]}" ]] || PP_SCOPE_EDITORS[$sk]="$PP_DEFAULT_EDITOR"
  done
}

# --------------------------- Project Listing ---------------------------------
_pp_exclude_args_fd() {  # colon-delimited → repeated -E args
  local X="$1" out=()
  local x; IFS=:; for x in $X; do [[ -n "$x" ]] && out+=(-E "$x"); done
  print -r -- "${(q@)out}"
}
_pp_exclude_args_find() { # colon-delimited → -not -path patterns
  local X="$1" out=()
  local x; IFS=:; for x in $X; do
    [[ -n "$x" ]] && out+=( -not -path "*/$x/*" )
  done
  print -r -- "${(q@)out}"
}

_pp_list_projects_one_root() {
  local root="$1" depth="$2" include_ws="$3" excludes="$4"
  # Using fd if available
  if _pp_have fd; then
    local -a ex; eval "ex=($( _pp_exclude_args_fd "$excludes" ))"
    fd -a -t d -d "$depth" . "$root" $ex
    if [[ "$include_ws" == "true" || "$include_ws" == "1" ]]; then
      fd -a -t f -d "$depth" --extension code-workspace . "$root" $ex
    fi
  else
    # Fallback to find (slower)
    local -a exf; eval "exf=($( _pp_exclude_args_find "$excludes" ))"
    command find "$root" -maxdepth "$depth" -type d "${exf[@]}"
    if [[ "$include_ws" == "true" || "$include_ws" == "1" ]]; then
      command find "$root" -maxdepth "$depth" -type f -name '*.code-workspace' "${exf[@]}"
    fi
  fi
}

_pp_build_cache_for_key() {
  local key="$1"
  local cache="$(_pp_cache "$key")"
  # Merge per-scope overrides with globals
  local depth="${PP_SCOPE_DEPTH[$key]:-$PP_DEPTH}"
  local incws="${PP_SCOPE_INCLUDE_WS[$key]:-$PP_INCLUDE_WORKSPACES}"
  local excludes="${PP_SCOPE_EXCLUDES[$key]:-$PP_EXCLUDES}"

  if [[ ! -s "$cache" || -n "$(find "$cache" -mmin +$PP_CACHE_TTL_MIN 2>/dev/null)" ]]; then
    : >| "$cache"
    local paths="${PP_SCOPE_PATHS[$key]}"
    local r
  IFS=:; for r in $paths; do
      [[ -d "$r" ]] || continue
      _pp_list_projects_one_root "$r" "$depth" "$incws" "$excludes" >> "$cache"
    done
  fi
  echo "$cache"
}

_pp_build_cache_all() {
  local cache="$(_pp_cache all)"
  if [[ ! -s "$cache" || -n "$(find "$cache" -mmin +$PP_CACHE_TTL_MIN 2>/dev/null)" ]]; then
    : >| "$cache"
    local k
    for k in "${(@k)PP_SCOPE_PATHS}"; do
      cat "$(_pp_build_cache_for_key "$k")" >> "$cache"
    done
  fi
  echo "$cache"
}

# --------------------------- Picker (fzf or menu) ----------------------------
_pp_pick_from_list() {
  local -a items; items=("$@")
  (( ${#items[@]} )) || return 1
  if _pp_have fzf; then
    printf '%s\n' "${items[@]}" | fzf --prompt="Project > " --height=80% --layout=reverse --border \
      ${PP_PREVIEW:="tree"} > /dev/null
  fi

  if _pp_have fzf; then
    # with preview if tree available and enabled
    if [[ "$PP_PREVIEW" == "tree" && $(_pp_have tree; echo $?) -eq 0 ]]; then
      printf '%s\n' "${items[@]}" | fzf --prompt="Project > " --height=80% --layout=reverse --border \
        --preview='if [[ -d {} ]]; then tree -a -L 2 "{}"; else echo ".code-workspace:"; head -n 120 "{}"; fi' \
        --preview-window=right:60%
    else
      printf '%s\n' "${items[@]}" | fzf --prompt="Project > " --height=80% --layout=reverse --border
    fi
  else
    # Numbered menu fallback
    local i=1
    for it in "${items[@]}"; do printf '%2d) %s\n' $i "$it"; ((i++)); done
    printf "Select (q to cancel): "
    local n; read -r n
    [[ "$n" == "q" || -z "$n" ]] && return 1
    if [[ "$n" -ge 1 && "$n" -le ${#items[@]} ]]; then
      print -r -- "${items[$n]}"
    else
      return 1
    fi
  fi
}

# --------------------------- Scope Helpers -----------------------------------
_pp_key_for_path() {
  local sel="$1" k paths r
  for k in "${(@k)PP_SCOPE_PATHS}"; do
  paths="${PP_SCOPE_PATHS[$k]}"
  IFS=:; for r in $paths; do
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
# --------------------------- ppicker Integration ----------------------------
# Run ppicker doctor from plugin
p_doctor() {
  command zsh "$PP_CONFIG_FILE:h/../bin/ppicker" doctor
}
# Run ppicker init/config wizard from plugin
p_config() {
  command zsh "$PP_CONFIG_FILE:h/../bin/ppicker" init
}
  print -r -- "Options:"
  print -r -- "  -t                      cd into project instead of opening"
  print -r -- "  -e <editor>             Override editor (code|idea|cursor|windsurf|nvim|vim|codium|custom:/path)"
  print -r -- "  --help                  Show this help"
  print -r -- "Config: ${PP_CONFIG_FILE}"
}

# --------------------------- Core Actions ------------------------------------
_pp_open() {
  local action="$1" editor="$2" sel="$3"
  case "$action" in
    cd)     [[ -d "$sel" ]] && builtin cd "$sel" || builtin cd "$(dirname "$sel")" ;;
    custom) _pp_run_editor "$editor" "$sel" ;;
    *)      _pp_run_editor "$editor" "$sel" ;;
  esac
}

# --------------------------- Command: p (prompt) -----------------------------
p() {
  [[ "$1" == "--help" ]] && { _pp_help; return; }
  _pp_require
  _pp_load_toml

  local action="open" editor="" key="" OPTIND opt
  while getopts "te:" opt; do
    case "$opt" in
      t) action="cd" ;;
      e) editor="$OPTARG" ;;
    esac
  done
  shift $((OPTIND-1))

  # List keys
  local -a keys; keys=("${(@k)PP_SCOPE_PATHS}")
  if (( ${#keys[@]} == 0 )); then _pp_die "no scopes configured"; fi

  print -r -- "Scopes: ${keys[*]}  (or 'all')"
  printf "Choose scope key (default 'all'): "
  read -r key
  [[ -z "$key" ]] && key="all"

  local cache sel chosen_key label chosen_editor
  if [[ "$key" == "all" ]]; then
    cache="$(_pp_build_cache_all)"
    local -a items; items=("${(@f)$(<"$cache")}")
    sel="$(_pp_pick_from_list "${items[@]}")" || return
    chosen_key="$(_pp_key_for_path "$sel")"
  else
    if [[ -z "${PP_SCOPE_PATHS[$key]}" ]]; then _pp_die "unknown scope key: $key"; fi
    cache="$(_pp_build_cache_for_key "$key")"
    local -a items; items=("${(@f)$(<"$cache")}")
    sel="$(_pp_pick_from_list "${items[@]}")" || return
    chosen_key="$key"
  fi

  [[ -z "$sel" ]] && return
  [[ -z "$chosen_key" ]] && chosen_key="$(_pp_key_for_path "$sel")"

  label="${PP_SCOPE_LABELS[$chosen_key]:-$chosen_key}"
  chosen_editor="${editor:-${PP_SCOPE_EDITORS[$chosen_key]:-$PP_DEFAULT_EDITOR}}"

  # persist last and log
  print -r -- "$sel" >| "$(_pp_last "$chosen_key")"
  _pp_log "$label" "${action:-open}" "$sel"
  _pp_announce "$label" "${action:-open}" "$chosen_editor" "$sel"
  if [[ "$action" == "cd" ]]; then _pp_open cd "" "$sel"; else _pp_open open "$chosen_editor" "$sel"; fi
}

# --------------------- Generate p<key> / p<key>l per scope -------------------
_pp_define_scope_cmds() {
  local k
  for k in "${(@k)PP_SCOPE_PATHS}"; do
    eval "
p$k() {
  [[ \"\$1\" == \"--help\" ]] && { _pp_help; return; }
  _pp_require
  _pp_load_toml
  local action=\"open\" editor=\"\" OPTIND opt
  while getopts \"te:\" opt; do case \"\$opt\" in t) action=\"cd\";; e) editor=\"\$OPTARG\";; esac; done
  shift \$((OPTIND-1))
  local cache=\"\$(_pp_build_cache_for_key $k)\"
  local -a items; items=(\${(@f)\$(<\"\$cache\")})
  local sel; sel=\"\$(_pp_pick_from_list \"\${items[@]}\")\" || return
  [[ -z \"\$sel\" ]] && return
  local label=\"\${PP_SCOPE_LABELS[$k]:-$k}\"
  local chosen_editor=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  print -r -- \"\$sel\" >| \"\$(_pp_last $k)\"
  _pp_log \"\$label\" \"\${action:-open}\" \"\$sel\"
  _pp_announce \"\$label\" \"\${action:-open}\" \"\$chosen_editor\" \"\$sel\"
  if [[ \"\$action\" == \"cd\" ]]; then _pp_open cd \"\" \"\$sel\"; else _pp_open open \"\$chosen_editor\" \"\$sel\"; fi
}
p${k}l() {
  [[ \"\$1\" == \"--help\" ]] && { _pp_help; return; }
  _pp_require
  _pp_load_toml
  local action=\"open\" editor=\"\" OPTIND opt
  while getopts \"te:\" opt; do case \"\$opt\" in t) action=\"cd\";; e) editor=\"\$OPTARG\";; esac; done
  shift \$((OPTIND-1))
  local f=\"\$(_pp_last $k)\"
  [[ -s \"\$f\" ]] || { _pp_warn \"No last \${PP_SCOPE_LABELS[$k]:-$k} project yet.\"; return 1; }
  local sel; sel=\"\$(<\"\$f\")\"
  local label=\"\${PP_SCOPE_LABELS[$k]:-$k}\"
  local chosen_editor=\"\${editor:-\${PP_SCOPE_EDITORS[$k]:-$PP_DEFAULT_EDITOR}}\"
  _pp_log \"\$label\" \"\${action:-open}\" \"\$sel\"
  _pp_announce \"\$label\" \"\${action:-open}\" \"\$chosen_editor\" \"\$sel\"
  if [[ \"\$action\" == \"cd\" ]]; then _pp_open cd \"\" \"\$sel\"; else _pp_open open \"\$chosen_editor\" \"\$sel\"; fi
}
"
  done
}

# --------------------------- Initialization ----------------------------------
# Load config & define commands for existing scopes
_pp_load_toml
_pp_define_scope_cmds
