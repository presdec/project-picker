# ~/.pp_diag.zsh — run:  zsh ~/.pp_diag.zsh
set -u
autoload -Uz colors; colors || true
whence -v p || echo "p: not found"

print -- "\n--- NAMED DIRS ---"
zmodload -F zsh/parameter || true
print -r -- "${(kv)nameddirs}" | sed 's/ /\n/g' | sort || true
hash -d || true   # will list mappings if any

print -- "\n--- ALIASES/FUNCTIONS ---"
alias -L | LC_ALL=C sort
typeset -f p >/dev/null 2>&1 && echo "p is a function" || echo "p is NOT a function"

print -- "\n--- HOOKS/PROMPTS ---"
( print -r -- "preexec_functions: ${(j:,:)preexec_functions}" ) 2>/dev/null || echo "preexec_functions: <unset>"
( print -r -- "precmd_functions:  ${(j:,:)precmd_functions}" ) 2>/dev/null || echo "precmd_functions:  <unset>"
print -r -- "PROMPT=${PROMPT:-<unset>}"
print -r -- "RPROMPT=${RPROMPT:-<unset>}"

print -- "\n--- TRACE EARLY WRITE ---"
tmp=$(mktemp /tmp/pprogue.XXXX) || exit 1
# Capture anything written BEFORE our function prints
exec {__SOUT}>&1 {__SERR}>&2
exec 1>"$tmp" 2>&1
# Common emitters that themselves can print
(( $+nameddirs[p] ))   && unhash -d -- p
(( $+nameddirs[pw] ))  && unhash -d -- pw
(( $+nameddirs[tok] )) && unhash -d -- tok
# Restore output
exec 1>&$__SOUT 2>&$__SERR
exec {__SOUT}>&- {__SERR}>&-

# Fire a dummy command name that is GUARANTEED not to exist
__NONCE=zzpp_$RANDOM$RANDOM
print -r -- "Calling: $__NONCE"
$__NONCE 2>/dev/null || true

print -- "\n--- CAPTURED BEFORE BODY ---"
sed -n '1,50p' "$tmp" | nl
rm -f "$tmp"

print -- "\n--- GREP DOTFILES FOR EMITTERS ---"
for f in ~/.zshenv ~/.zprofile ~/.zshrc ~/.zlogin ~/.zlogout ~/.p10k.zsh ~/.config/zsh/**/*(.N); do
  [[ -r $f ]] || continue
  grep -nE '(^|[^#])(hash -d[[:space:]]+[[:alnum:]_]+$|typeset -h[[:space:]]+[[:alnum:]_]+|print -P[[:space:]]+~[[:alnum:]_]+|echo[[:space:]]+[[:alnum:]_]+=/.+)' "$f" && echo "=> $f"
done
echo "\nDONE"
