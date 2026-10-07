#!/usr/bin/env bash
# Profile loading, validation, and agent-frontmatter rendering, shared by
# install.sh and uninstall.sh. Source this file; it defines functions only,
# no side effects.
#
# No python3, node, or jq is assumed on PATH (see git_guard.sh and
# edit-check.sh for the same stance elsewhere in this repo), so this reads
# the profile JSON with plain grep/sed/awk instead of a real JSON parser.
# That only works because the shape is fixed and this repo controls the
# formatting of every profiles/*.json file it ships: one key per line at a
# known indent, and each role as a single-line object
# `"role": { "model": "...", "effort": "..." }`. A profile file that does
# not look like that (hand-edited into a different layout, truncated,
# missing a brace) is reported as malformed rather than guessed at.
#
# profile.ps1 is the same contract for PowerShell, using real JSON parsing
# (ConvertFrom-Json) since that needs no extra dependency there. The two
# are implemented separately but must agree on what counts as valid and on
# where "agents" links for each profile.

PROFILE_REQUIRED_TOP="name description main workflowMode maxParallelTeammates roles"
# Allowed but not required: a profile that omits one falls back to this
# kit's own default (see each key's own reader -- session_context.py's
# resolve_context_cap, for sessionContextChars). Keeping these OUT of
# PROFILE_REQUIRED_TOP is what lets an older or hand-written profile
# file, missing a key added later, still validate.
PROFILE_OPTIONAL_TOP="sessionContextChars"
PROFILE_REQUIRED_MAIN="model effortLevel"
PROFILE_REQUIRED_ROLE_FIELDS="model effort"
PROFILE_REQUIRED_ROLES="planner plan-reviewer builder adversarial-reviewer probe plan-reviewer-critical builder-critical"
PROFILE_VALID_WORKFLOW_MODES="full lean solo"

# profile_valid_names <profilesDir> -- one name per line, derived from the
# files actually present (not a second list that could drift from them).
profile_valid_names() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    basename "$f" .json
  done | sort
}

# _word_in_list <word> <space-separated list> -- true if word is one of the
# list's space-separated entries (exact match, not a substring match).
_word_in_list() {
  local word="$1" list="$2" w
  for w in $list; do
    [ "$w" = "$word" ] && return 0
  done
  return 1
}

# _missing_from_list <wanted list> <have list> -- wanted entries not present
# in have, space-separated, empty if none.
_missing_from_list() {
  local wanted="$1" have="$2" w out=""
  for w in $wanted; do
    _word_in_list "$w" "$have" || out="$out $w"
  done
  printf '%s' "${out# }"
}

# profile_validate <path> -- prints nothing and returns 0 if the file is a
# valid profile; otherwise prints one error line to stdout and returns 1.
# Never touches anything outside the file it is given.
profile_validate() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf 'profile file not found: %s\n' "$path"
    return 1
  fi

  # Structural sanity: strip quoted-string contents (so a brace inside a
  # string, e.g. in a description, is not counted) and require the braces
  # that remain to balance and the file to start/end with one.
  local stripped
  stripped=$(sed -E 's/"([^"\\]|\\.)*"/""/g' "$path")
  local first last opens closes
  first=$(printf '%s' "$stripped" | grep -m1 -v '^[[:space:]]*$' | sed -E 's/^[[:space:]]*//')
  last=$(printf '%s' "$stripped" | grep -v '^[[:space:]]*$' | tail -1 | sed -E 's/[[:space:]]*$//')
  if [ "${first:0:1}" != "{" ] || [ "${last: -1}" != "}" ]; then
    printf 'malformed profile JSON in %s: does not start/end with a single JSON object\n' "$path"
    return 1
  fi
  opens=$(printf '%s' "$stripped" | tr -cd '{' | wc -c)
  closes=$(printf '%s' "$stripped" | tr -cd '}' | wc -c)
  if [ "$opens" -eq 0 ] || [ "$opens" -ne "$closes" ]; then
    printf 'malformed profile JSON in %s: braces do not balance\n' "$path"
    return 1
  fi

  local top_keys main_keys role_keys
  top_keys=$(grep -E '^  "[A-Za-z]+"[[:space:]]*:' "$path" | sed -E 's/^  "([A-Za-z]+)".*/\1/' | tr '\n' ' ')
  if [ -z "$(printf '%s' "$top_keys" | tr -d '[:space:]')" ]; then
    printf 'malformed profile JSON in %s: no top-level keys found at the expected indent\n' "$path"
    return 1
  fi
  local missing extra
  missing=$(_missing_from_list "$PROFILE_REQUIRED_TOP" "$top_keys")
  [ -n "$missing" ] && { printf 'missing top-level key(s) in %s: %s\n' "$path" "$missing"; return 1; }
  extra=$(_missing_from_list "$top_keys" "$PROFILE_REQUIRED_TOP $PROFILE_OPTIONAL_TOP")
  [ -n "$extra" ] && { printf 'unknown top-level key(s) in %s: %s\n' "$path" "$extra"; return 1; }

  local mode
  mode=$(profile_field "$path" workflowMode)
  if ! _word_in_list "$mode" "$PROFILE_VALID_WORKFLOW_MODES"; then
    printf 'workflowMode must be one of: %s (got '"'"'%s'"'"') in %s\n' "$PROFILE_VALID_WORKFLOW_MODES" "$mode" "$path"
    return 1
  fi

  if _word_in_list "sessionContextChars" "$top_keys"; then
    local cap
    cap=$(profile_field "$path" sessionContextChars)
    if ! [[ "$cap" =~ ^[0-9]+$ ]] || [ "$cap" -le 0 ]; then
      printf 'sessionContextChars must be a positive integer (got '"'"'%s'"'"') in %s\n' "$cap" "$path"
      return 1
    fi
  fi

  main_keys=$(awk '/^  "main": \{/{inmain=1; next} inmain && /^  \}/{inmain=0; next} inmain' "$path" |
    grep -E '^    "[A-Za-z]+"[[:space:]]*:' | sed -E 's/^    "([A-Za-z]+)".*/\1/' | tr '\n' ' ')
  missing=$(_missing_from_list "$PROFILE_REQUIRED_MAIN" "$main_keys")
  [ -n "$missing" ] && { printf 'missing main key(s) in %s: %s\n' "$path" "$missing"; return 1; }
  extra=$(_missing_from_list "$main_keys" "$PROFILE_REQUIRED_MAIN")
  [ -n "$extra" ] && { printf 'unknown main key(s) in %s: %s\n' "$path" "$extra"; return 1; }

  role_keys=$(awk '/^  "roles": \{/{inroles=1; next} inroles && /^  \}/{inroles=0; next} inroles' "$path" |
    grep -E '^    "[a-z-]+"[[:space:]]*:' | sed -E 's/^    "([a-z-]+)".*/\1/' | tr '\n' ' ')
  missing=$(_missing_from_list "$PROFILE_REQUIRED_ROLES" "$role_keys")
  [ -n "$missing" ] && { printf 'missing role(s) in %s: %s\n' "$path" "$missing"; return 1; }
  extra=$(_missing_from_list "$role_keys" "$PROFILE_REQUIRED_ROLES")
  [ -n "$extra" ] && { printf 'unknown role(s) in %s: %s\n' "$path" "$extra"; return 1; }

  local r line
  for r in $PROFILE_REQUIRED_ROLES; do
    line=$(awk -v role="\"$r\":" '$0 ~ "^    " role {print; exit}' "$path")
    if [ -z "$line" ]; then
      printf 'role '"'"'%s'"'"' not found as a single-line object in %s\n' "$r" "$path"
      return 1
    fi
    if ! printf '%s' "$line" | grep -Eq '^    "'"$r"'":[[:space:]]*\{[[:space:]]*"model":[[:space:]]*"[^"]+",[[:space:]]*"effort":[[:space:]]*"[^"]+"[[:space:]]*\}'; then
      printf 'role '"'"'%s'"'"' in %s does not have exactly model and effort\n' "$r" "$path"
      return 1
    fi
  done

  return 0
}

# profile_field <path> <key> -- a top-level scalar field's value (name,
# description, workflowMode, maxParallelTeammates). Not for main/roles.
# Strips only the key, the trailing comma, and one pair of surrounding
# quotes if the value has them (a number like maxParallelTeammates does
# not) -- it does NOT stop at the first comma inside the value, because
# "description" is free text that legitimately contains commas.
profile_field() {
  local path="$1" key="$2" raw
  raw=$(grep -m1 -E '^  "'"$key"'"[[:space:]]*:' "$path" |
    sed -E 's/^  "'"$key"'"[[:space:]]*:[[:space:]]*//' |
    sed -E 's/,[[:space:]]*$//')
  if [[ "$raw" == \"*\" ]]; then
    raw="${raw#\"}"
    raw="${raw%\"}"
  fi
  printf '%s' "$raw"
}

# profile_main_field <path> <model|effortLevel>
profile_main_field() {
  local path="$1" key="$2"
  awk '/^  "main": \{/{inmain=1; next} inmain && /^  \}/{inmain=0; next} inmain' "$path" |
    grep -m1 -E '^    "'"$key"'"[[:space:]]*:' |
    sed -E 's/^    "'"$key"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
}

# profile_role_field <path> <role> <model|effort>
profile_role_field() {
  local path="$1" role="$2" field="$3" line
  line=$(awk -v role="\"$role\":" '$0 ~ "^    " role {print; exit}' "$path")
  printf '%s' "$line" | sed -E 's/.*"'"$field"'":[[:space:]]*"([^"]*)".*/\1/'
}

# profile_render_agents <profileJson> <srcDir> <destDir> <dry: 0|1>
#                        <diffOutFile> --
# Renders every agent file from srcDir into destDir: the 7 role files get
# only their `model:` and `effort:` frontmatter lines replaced, everything
# else (including line endings) copied through unchanged -- awk's record
# separator is the input's own, and ORS is left at the default "\n" to
# match this repo's LF-only agent files, never a tool that could normalize
# endings or add a BOM; any OTHER `*.md` file in srcDir (not one of the 7
# roles) is copied through byte for byte, so a file added to agents/
# later is present for every profile, not just max.
#
# Built in a sibling temp folder first and swapped into destDir only on
# complete success: a failure partway through returns 1 BEFORE destDir is
# ever touched, leaving an earlier render there (if any) exactly as it
# was, not half-overwritten.
#
# One tab-separated diff line per role (role, old model, new model, old
# effort, new effort) is APPENDED to diffOutFile, not printed to stdout:
# `profile_render_agents ... | while read ...` cannot be trusted to
# surface this function's own exit status reliably to a caller that
# forgets to check it (the pipeline's status reflects the pipe as a
# whole). Call this directly in an `if`, then read diffOutFile separately.
profile_render_agents() {
  local profile="$1" src="$2" dest="$3" dry="$4" diff_out="$5"
  local role srcFile model effort old_model old_effort tmp_dir f base
  : >"$diff_out"

  if [ "$dry" -eq 0 ]; then
    tmp_dir="$dest.tmp-$$"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
  fi

  for role in $PROFILE_REQUIRED_ROLES; do
    srcFile="$src/$role.md"
    if [ ! -f "$srcFile" ]; then
      echo "render: agent file not found: $srcFile" >&2
      [ -n "${tmp_dir:-}" ] && rm -rf "$tmp_dir"
      return 1
    fi
    model=$(profile_role_field "$profile" "$role" "model")
    effort=$(profile_role_field "$profile" "$role" "effort")
    if [ -z "$model" ] || [ -z "$effort" ]; then
      echo "render: could not read model/effort for role $role from $profile" >&2
      [ -n "${tmp_dir:-}" ] && rm -rf "$tmp_dir"
      return 1
    fi

    if [ "$(sed -n '1p' "$srcFile")" != "---" ]; then
      echo "render: $srcFile does not start with a frontmatter delimiter (---)" >&2
      [ -n "${tmp_dir:-}" ] && rm -rf "$tmp_dir"
      return 1
    fi
    old_model=$(sed -n '2,/^---$/p' "$srcFile" | grep -m1 -E '^model:' | sed -E 's/^model:[[:space:]]*//')
    old_effort=$(sed -n '2,/^---$/p' "$srcFile" | grep -m1 -E '^effort:' | sed -E 's/^effort:[[:space:]]*//')
    if [ -z "$old_model" ] || [ -z "$old_effort" ]; then
      echo "render: $srcFile is missing a model: or effort: line in its frontmatter" >&2
      [ -n "${tmp_dir:-}" ] && rm -rf "$tmp_dir"
      return 1
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$role" "$old_model" "$model" "$old_effort" "$effort" >>"$diff_out"

    if [ "$dry" -eq 0 ]; then
      awk -v nm="$model" -v ne="$effort" '
        BEGIN { infm = 0; fmdone = 0 }
        NR == 1 && $0 == "---" { infm = 1; print; next }
        infm && !fmdone && $0 == "---" { fmdone = 1; infm = 0; print; next }
        infm && $0 ~ /^model:/ { print "model: " nm; next }
        infm && $0 ~ /^effort:/ { print "effort: " ne; next }
        { print }
      ' "$srcFile" >"$tmp_dir/$role.md"
    fi
  done

  if [ "$dry" -eq 0 ]; then
    for f in "$src"/*.md; do
      [ -f "$f" ] || continue
      base=$(basename "$f" .md)
      if ! _word_in_list "$base" "$PROFILE_REQUIRED_ROLES"; then
        cp "$f" "$tmp_dir/$(basename "$f")"
      fi
    done
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    mv "$tmp_dir" "$dest"
  fi
}

# profile_render_settings <profileJson> <srcSettings> <destSettings>
#                          <dry: 0|1> --
# Renders srcSettings (global/settings.json) into destSettings for a
# non-max profile: replaces ONLY the top-level "model" and "effortLevel"
# values and the "modelSettings" block's two per-model effortLevel
# values (both set to this profile's own main.effortLevel, so manually
# switching models mid-session under this profile does not jump to a
# different effort than the profile already chose). Every other key,
# line, and line ending is kept exactly as in srcSettings -- a targeted
# text substitution on this repo's own fixed, known layout, the same
# technique profile_render_agents uses on the agent files, not a real
# JSON round-trip that could reformat or reorder anything.
#
# Written to a sibling temp file first and renamed into place, so a
# failure never leaves destSettings partial. With dry=1, nothing is
# written; this only validates that srcSettings has the expected shape.
profile_render_settings() {
  local profile="$1" src="$2" dest="$3" dry="$4"
  local model effort tmp

  model=$(profile_main_field "$profile" model)
  effort=$(profile_main_field "$profile" effortLevel)
  if [ -z "$model" ] || [ -z "$effort" ]; then
    echo "render: could not read main.model/effortLevel from $profile" >&2
    return 1
  fi
  if [ "$(sed -n '1p' "$src")" != "{" ]; then
    echo "render: $src does not start with a bare {" >&2
    return 1
  fi
  if ! grep -qE '^  "model":' "$src" || ! grep -qE '^  "effortLevel":' "$src"; then
    echo "render: $src is missing a top-level model/effortLevel key in the expected shape" >&2
    return 1
  fi
  if ! grep -qE '^  "modelSettings": \{$' "$src"; then
    echo "render: $src is missing a modelSettings block in the expected shape" >&2
    return 1
  fi

  [ "$dry" -eq 1 ] && return 0

  tmp="$dest.tmp-$$"
  mkdir -p "$(dirname "$tmp")"
  # Walks each "<model-id>": { "effortLevel": "..." } entry inside
  # modelSettings individually, so an entry for a model THIS profile
  # does not mention (added by hand, or a model this repo adds later)
  # passes through completely untouched -- only the two model ids this
  # profile actually sets (claude-opus-5-5, claude-sonnet-5) get their
  # effortLevel value replaced; nothing is ever added or removed, and no
  # entry is rebuilt from scratch.
  awk -v nm="$model" -v ne="$effort" '
    BEGIN { inms = 0; curmodel = "" }
    /^  "model":/ { print "  \"model\": \"" nm "\","; next }
    /^  "effortLevel":/ { print "  \"effortLevel\": \"" ne "\","; next }
    /^  "modelSettings": \{$/ { inms = 1; print; next }
    inms && /^  \},?$/ { inms = 0; print; next }
    inms && /^    "[^"]+": \{$/ {
      curmodel = $0
      sub(/^    "/, "", curmodel)
      sub(/": \{$/, "", curmodel)
      print
      next
    }
    inms && /^      "effortLevel":/ {
      if (curmodel == "claude-opus-5-5" || curmodel == "claude-sonnet-5") {
        sub(/"[^"]*"[[:space:]]*$/, "\"" ne "\"")
      }
      print
      next
    }
    { print }
  ' "$src" >"$tmp"
  mv "$tmp" "$dest"
}

# profile_validate_max_consistency <maxProfileJson> <agentsDir>
#                                   <settingsJson> --
# For the max profile specifically: max.json carries values that are
# NEVER rendered anywhere (max links agents/ and settings.json straight
# from the repo, unchanged), so nothing else enforces that it still
# matches the agent files' own frontmatter or settings.json's own
# top-level model/effortLevel. Prints which role or field drifted and
# returns 1 if so, rather than silently installing from the (correct)
# agent files and settings.json while printing a "model X -> Y" change
# from max.json that is never actually applied.
profile_validate_max_consistency() {
  local profile="$1" agents_dir="$2" settings="$3"
  local role model effort old_model old_effort main_model main_effort s_model s_effort

  for role in $PROFILE_REQUIRED_ROLES; do
    model=$(profile_role_field "$profile" "$role" "model")
    effort=$(profile_role_field "$profile" "$role" "effort")
    old_model=$(sed -n '2,/^---$/p' "$agents_dir/$role.md" | grep -m1 -E '^model:' | sed -E 's/^model:[[:space:]]*//')
    old_effort=$(sed -n '2,/^---$/p' "$agents_dir/$role.md" | grep -m1 -E '^effort:' | sed -E 's/^effort:[[:space:]]*//')
    if [ "$model" != "$old_model" ] || [ "$effort" != "$old_effort" ]; then
      echo "profiles/max.json role '$role' (model=$model effort=$effort) does not match $agents_dir/$role.md (model=$old_model effort=$old_effort). To change max, edit the agent files AND max.json together." >&2
      return 1
    fi
  done

  main_model=$(profile_main_field "$profile" model)
  main_effort=$(profile_main_field "$profile" effortLevel)
  s_model=$(grep -m1 -E '^  "model":' "$settings" | sed -E 's/^  "model":[[:space:]]*"([^"]*)".*/\1/')
  s_effort=$(grep -m1 -E '^  "effortLevel":' "$settings" | sed -E 's/^  "effortLevel":[[:space:]]*"([^"]*)".*/\1/')
  if [ "$main_model" != "$s_model" ] || [ "$main_effort" != "$s_effort" ]; then
    echo "profiles/max.json main (model=$main_model effortLevel=$main_effort) does not match $settings (model=$s_model effortLevel=$s_effort). To change max, edit settings.json AND max.json together." >&2
    return 1
  fi
}

# profile_record_name <recordPath> -- the "name" field of a profile record
# this installer previously wrote, or "max" if there is none / it cannot be
# read. A plain single-key read (like edit-check.sh's file_path pull), not
# the full validator, because by the time this is called the record is
# trusted content this installer wrote, not user input to validate.
profile_record_name() {
  local record="$1" n
  [ -f "$record" ] || { printf 'max'; return 0; }
  n=$(grep -m1 -E '^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$record" |
    sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  [ -z "$n" ] && n="max"
  printf '%s' "$n"
}

# profile_agents_source <here> <target> -- the directory "agents" should
# link to for whichever profile is recorded at
# <target>/claude-setup-profile.json (max, or no record yet: the repo's
# own agents/; anything else: that profile's OWN rendered
# .profile-build/<name>/agents, never shared with any other profile's
# target).
profile_agents_source() {
  local here="$1" target="$2" name
  name=$(profile_record_name "$target/claude-setup-profile.json")
  if [ "$name" = "max" ]; then
    printf '%s/agents' "$here"
  else
    printf '%s/.profile-build/%s/agents' "$here" "$name"
  fi
}

# profile_settings_source <here> <target> -- the same resolution as
# profile_agents_source, for "settings.json": max: global/settings.json
# itself; anything else: that profile's own rendered
# .profile-build/<name>/settings.json. settings.json is installed as a
# plain copy for every non-max profile (see install.sh's
# install_profile_settings), so this mostly matters if settings.json is
# somehow still a link at that path (a manual edit, or a manifest line
# that was never refreshed); uninstall needs the right source either way
# to tell whether a link still resolves into this repo before removing it.
profile_settings_source() {
  local here="$1" target="$2" name
  name=$(profile_record_name "$target/claude-setup-profile.json")
  if [ "$name" = "max" ]; then
    printf '%s/global/settings.json' "$here"
  else
    printf '%s/.profile-build/%s/settings.json' "$here" "$name"
  fi
}

# profile_menu_order <space-separated valid names> -- max first (the most
# familiar choice), then standard, then lite, NOT the alphabetical order
# profile_valid_names returns; filtered to whatever actually exists, so a
# missing file just drops out instead of breaking the menu. Any OTHER
# profile this repo ever grows is appended after these three, in whatever
# order it was given, so the menu never silently omits a real profile.
profile_menu_order() {
  local valid=" $1 " preferred="max standard lite" p
  for p in $preferred; do
    case "$valid" in *" $p "*) printf '%s\n' "$p" ;; esac
  done
  for p in $1; do
    case " $preferred " in *" $p "*) ;; *) printf '%s\n' "$p" ;; esac
  done
}

# profile_prompt_choice <profilesDir> <menuOrder, one name per line via
# stdin-safe args: pass as "$@" from the caller> -- prints the menu and
# "Not a valid choice" retries to STDERR (so a caller capturing this
# function's stdout via command substitution, $(...), gets only the
# chosen name, never the menu text) and reads from stdin with `read`,
# which still reaches the real terminal from inside $(...) as long as
# stdin itself was never redirected -- exactly the case already ruled out
# before this is ever called (see install.sh's interactive check).
# Accepts a 1-based index, a profile name (case-insensitive), or an empty
# line for the default (the first menu entry); retries up to 3 times, and
# returns non-zero with nothing printed on stdout if all 3 are invalid.
profile_prompt_choice() {
  local profiles_dir="$1"
  shift
  local menu=("$@")
  local count=${#menu[@]}
  {
    echo "Which Claude plan do you have? This sets the models, effort, and how many teammates run at once."
    echo ""
    local i=1 name desc
    for name in "${menu[@]}"; do
      desc=$(profile_field "$profiles_dir/$name.json" description)
      printf "  %d) %-10s %s\n" "$i" "$name" "$desc"
      i=$((i + 1))
    done
    echo ""
    echo "Not sure? Pick the cheaper one; you can switch later with: install.sh --update --profile <name>"
  } >&2

  local attempt=1 raw trimmed lower target
  while [ "$attempt" -le 3 ]; do
    printf "Choice [1-%d, default 1]: " "$count" >&2
    if ! IFS= read -r raw; then
      return 1
    fi
    trimmed=$(printf '%s' "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    if [ -z "$trimmed" ]; then
      printf '%s' "${menu[0]}"
      return 0
    fi
    if [[ "$trimmed" =~ ^[0-9]+$ ]]; then
      if [ "$trimmed" -ge 1 ] && [ "$trimmed" -le "$count" ]; then
        printf '%s' "${menu[$((trimmed - 1))]}"
        return 0
      fi
    else
      lower=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')
      for name in "${menu[@]}"; do
        if [ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" = "$lower" ]; then
          printf '%s' "$name"
          return 0
        fi
      done
    fi
    echo "Not a valid choice. Enter 1-$count or a profile name." >&2
    attempt=$((attempt + 1))
  done
  return 1
}

# profile_to_winpath <unixPath> -- best-effort Windows-style conversion
# of a Unix-style absolute path (/c/Users/... -> C:\Users\...), used
# only to make the PowerShell example command in
# profile_required_message look like something you would actually type
# on Windows; a non-Windows-drive-shaped path (no leading /<letter>/)
# passes through unchanged, which is correct on real Mac/Linux, where
# there is no Windows path to show at all.
profile_to_winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1" | sed -E 's#^/([a-zA-Z])/#\1:/#' | sed 's#/#\\#g'
  fi
}

# profile_required_message <profilesDir> <yesGiven 0|1> <targetArg, may
# be empty> <menuOrder, one name per line via "$@"> -- printed when a
# profile cannot be chosen without asking (a first-time install, no
# --profile, running non-interactively or with --yes): there is no safe
# default to fall back on, so this names the three profiles with their
# own description (never duplicated by hand, same as
# profile_prompt_choice), the exact command for each shell (carrying
# over targetArg, if one was given, converted to THAT shell's own path
# style -- profile_to_winpath for the PowerShell example, as-is for the
# Mac/Linux one, since targetArg arrives in bash's own Unix style --
# and yesGiven distinguishing a real non-interactive run from --yes in
# a real console, so the message never claims the wrong one), and a
# line addressed to an AI assistant running the installer on someone
# else's behalf. Each example uses
# `powershell -ExecutionPolicy Bypass -File`, not `.\install.ps1`,
# since the latter fails outright under a Restricted execution policy.
profile_required_message() {
  local profiles_dir="$1" yes_given="$2" target_arg="$3"
  shift 3
  local name desc ps_target sh_target
  if [ "$yes_given" -eq 1 ]; then
    echo "A profile is required: --yes was given, but no profile is recorded yet and there is no safe default to fall back on." >&2
  else
    echo "A profile is required: this is a first-time install (no profile recorded yet) running non-interactively, so there is no safe default to fall back on." >&2
  fi
  echo "" >&2
  ps_target=""
  sh_target=""
  if [ -n "$target_arg" ]; then
    ps_target=" -Target \"$(profile_to_winpath "$target_arg")\""
    sh_target=" --target \"$target_arg\""
  fi
  for name in "$@"; do
    desc=$(profile_field "$profiles_dir/$name.json" description)
    printf "  %-10s %s\n" "$name" "$desc" >&2
    printf "    PowerShell: powershell -ExecutionPolicy Bypass -File install.ps1 -Profile %s%s\n" "$name" "$ps_target" >&2
    printf "    Mac/Linux:  ./install.sh --profile %s%s\n" "$name" "$sh_target" >&2
  done
  echo "" >&2
  echo "If you are an AI assistant running this for someone, ask them which plan they have and re-run with --profile <name>." >&2
}
