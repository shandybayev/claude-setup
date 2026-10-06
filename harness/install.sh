#!/usr/bin/env bash
# Wires the harness into a project. Copies harness/ in, points git hooks at
# it, adds the edit-time Claude Code hook, and drops the CI workflow. Never
# commits anything; prints a summary and leaves the rest to the user.
#
# Usage:
#   harness/install.sh [--target DIR] [--dry-run]
#   harness/install.sh --verify [--target DIR]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$HERE/.." && pwd)"
TARGET="$(pwd)"
DRY_RUN=0
VERIFY=0

while [ $# -gt 0 ]; do
  case "$1" in
  --target) TARGET="$2"; shift 2 ;;
  --dry-run) DRY_RUN=1; shift ;;
  --verify) VERIFY=1; shift ;;
  *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }
act() {
  # act <description> -- prints what would happen; runs the rest of the
  # command line for real unless DRY_RUN is set.
  local desc="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) $desc"
    return 0
  fi
  say "  $desc"
  "$@"
}

verify() {
  local ok=1
  cd "$TARGET" || { echo "x target not found: $TARGET"; exit 1; }

  check() {
    if eval "$2"; then
      say "OK   $1"
    else
      say "FAIL $1"
      ok=0
    fi
  }

  # A hook can exist and be +x and still not run: a BOM or other corruption
  # ahead of the shebang makes the kernel/git refuse it with "Exec format
  # error" even though the file is right there. Check the real bytes, not
  # just presence.
  hook_runnable() {
    [ -f "$1" ] || return 1
    head -c 2 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' | grep -qi '^2321$'
  }

  check "git on PATH" "command -v git >/dev/null 2>&1"
  check "bash on PATH" "command -v bash >/dev/null 2>&1"
  check "core.hooksPath is .githooks" "[ \"\$(git config --get core.hooksPath 2>/dev/null)\" = \".githooks\" ]"
  check ".githooks/pre-commit starts with #! (no BOM) and is executable" "hook_runnable .githooks/pre-commit && [ -x .githooks/pre-commit ]"
  check ".githooks/pre-push starts with #! (no BOM) and is executable" "hook_runnable .githooks/pre-push && [ -x .githooks/pre-push ]"
  check ".githooks/commit-msg starts with #! (no BOM) and is executable" "hook_runnable .githooks/commit-msg && [ -x .githooks/commit-msg ]"
  check "harness/gates.sh exists and is executable" "[ -x harness/gates.sh ]"
  check "harness/edit-check.sh exists and is executable" "[ -x harness/edit-check.sh ]"
  check "the PostToolUse edit-check hook is wired in .claude/settings.json" \
    "grep -q 'harness/edit-check.sh' .claude/settings.json 2>/dev/null"

  # The project's own configured commands, not just the harness scripts:
  # the brief asked for "the tools on PATH", and a gate that silently
  # no-ops because FORMAT_CMD names a tool nobody installed is a false
  # sense of security.
  if [ -f harness/harness.config ]; then
    for key in FORMAT_CMD LINT_CMD TYPECHECK_CMD TEST_CMD; do
      cmd=$(grep -E "^${key}=" harness/harness.config 2>/dev/null | tail -1 | cut -d= -f2-)
      [ -z "$cmd" ] && continue
      tool=$(printf '%s' "$cmd" | awk '{print $1}')
      check "$key's tool ('$tool') is on PATH" "command -v '$tool' >/dev/null 2>&1"
    done
  fi

  if [ "$ok" -eq 1 ]; then
    say "harness --verify: all checks passed."
    exit 0
  else
    say "x harness --verify: one or more checks failed."
    exit 1
  fi
}

[ "$VERIFY" -eq 1 ] && verify

mkdir -p "$TARGET"
cd "$TARGET" || exit 1
say "Installing the harness into: $TARGET"

# 1) Copy the harness scripts in. Never overwrite an existing harness.config:
#    that file is the project's own settings.
act "copy harness/ scripts" mkdir -p "$TARGET/harness/lib"
for f in gates.sh gates.ps1 edit-check.sh harness.config.example; do
  act "  harness/$f" cp "$KIT_ROOT/harness/$f" "$TARGET/harness/$f"
done
act "  harness/lib/scope.sh" cp "$KIT_ROOT/harness/lib/scope.sh" "$TARGET/harness/lib/scope.sh"
if [ ! -f "$TARGET/harness/harness.config" ]; then
  act "write harness/harness.config (from the example)" cp "$KIT_ROOT/harness/harness.config.example" "$TARGET/harness/harness.config"
else
  say "  harness/harness.config already exists, leaving it alone."
fi
[ "$DRY_RUN" -eq 0 ] && chmod +x "$TARGET/harness/gates.sh" "$TARGET/harness/edit-check.sh" 2>/dev/null

# 2) Git hooks.
act "create .githooks/" mkdir -p "$TARGET/.githooks"

write_hook() {
  local name="$1" body="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) write .githooks/$name"
    return 0
  fi
  printf '%s\n' "$body" >"$TARGET/.githooks/$name"
  chmod +x "$TARGET/.githooks/$name"
  say "  write .githooks/$name"
}

write_hook pre-commit '#!/usr/bin/env bash
exec bash "$(git rev-parse --show-toplevel)/harness/gates.sh" commit'

write_hook pre-push '#!/usr/bin/env bash
exec bash "$(git rev-parse --show-toplevel)/harness/gates.sh" push'

write_hook commit-msg '#!/usr/bin/env bash
exec bash "$(git rev-parse --show-toplevel)/harness/gates.sh" commit-msg "$1"'

if [ "$DRY_RUN" -eq 0 ] && [ -e "$TARGET/.git" ]; then
  act "set core.hooksPath to .githooks" git -C "$TARGET" config core.hooksPath .githooks
else
  say "  (dry run or no .git here) skipping: git config core.hooksPath .githooks"
fi

# 3) .gitattributes: force LF on the scripts and hooks this kit ships, so
# a commit made on Windows (no execute bit either way, and CRLF if the
# committer's git core.autocrlf mangled it) still runs on Mac/Linux/CI,
# which does not tolerate CRLF shell scripts the way Git Bash does.
# Idempotent: a line already present is never duplicated, and an existing
# file is appended to, never overwritten. Written with plain `printf`/`>>`,
# which never introduces a BOM or CRLF on its own.
write_gitattributes_line() {
  local line="$1" ga="$TARGET/.gitattributes"
  if [ -f "$ga" ] && grep -qxF "$line" "$ga" 2>/dev/null; then
    say "  .gitattributes already has: $line"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) add to .gitattributes: $line"
    return 0
  fi
  printf '%s\n' "$line" >>"$ga"
  say "  added to .gitattributes: $line"
}
for line in '*.sh text eol=lf' '.githooks/* text eol=lf' 'harness/** text eol=lf'; do
  write_gitattributes_line "$line"
done

# 4) Claude Code edit-time hook. Prefer python3, fall back to node; never
#    hand-edit JSON with sed, and never fail the whole install if neither
#    is available.
merge_settings() {
  local settings="$TARGET/.claude/settings.json"
  mkdir -p "$TARGET/.claude"
  local runner=""
  command -v python3 >/dev/null 2>&1 && runner="python3"
  [ -z "$runner" ] && command -v node >/dev/null 2>&1 && runner="node"
  if [ -z "$runner" ]; then
    say "  no python3 or node found: add the PostToolUse hook to .claude/settings.json by hand (see harness/README.md)."
    return 0
  fi
  if [ "$runner" = "python3" ]; then
    python3 - "$settings" <<'PYEOF'
import json, sys, os
path = sys.argv[1]
data = {}
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as fh:
        content = fh.read().strip()
        if content:
            data = json.loads(content)
entry = {
    "matcher": "Edit|Write",
    # $CLAUDE_PROJECT_DIR, not a cwd-relative path: a relative "harness/..."
    # only resolves when Claude Code happens to run the hook from the
    # project root, and fails silently (rc 127, treated as non-blocking)
    # from any subdirectory.
    "hooks": [{"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/harness/edit-check.sh', "timeout": 30}],
}
hooks = data.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])
if not any(h.get("matcher") == "Edit|Write" and
           any("harness/edit-check.sh" in (c.get("command") or "") for c in h.get("hooks", []))
           for h in post):
    post.append(entry)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print("  added PostToolUse hook to .claude/settings.json")
else:
    print("  .claude/settings.json already has the harness edit-check hook")
PYEOF
  else
    node - "$settings" <<'NODEEOF'
const fs = require("fs");
const path = process.argv[2];
let data = {};
if (fs.existsSync(path)) {
  const content = fs.readFileSync(path, "utf-8").trim();
  if (content) data = JSON.parse(content);
}
const entry = { matcher: "Edit|Write", hooks: [{ type: "command", command: 'bash "$CLAUDE_PROJECT_DIR"/harness/edit-check.sh', timeout: 30 }] };
data.hooks = data.hooks || {};
data.hooks.PostToolUse = data.hooks.PostToolUse || [];
const already = data.hooks.PostToolUse.some(
  (h) => h.matcher === "Edit|Write" && (h.hooks || []).some((c) => (c.command || "").includes("harness/edit-check.sh"))
);
if (!already) {
  data.hooks.PostToolUse.push(entry);
  fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n");
  console.log("  added PostToolUse hook to .claude/settings.json");
} else {
  console.log("  .claude/settings.json already has the harness edit-check hook");
}
NODEEOF
  fi
}

if [ "$DRY_RUN" -eq 1 ]; then
  say "  (dry run) merge the PostToolUse hook into .claude/settings.json"
else
  merge_settings
fi

# 5) CI workflow.
if [ ! -f "$TARGET/.github/workflows/gates.yml" ]; then
  act "write .github/workflows/gates.yml" bash -c "mkdir -p '$TARGET/.github/workflows' && cp '$KIT_ROOT/templates/ci/gates.yml' '$TARGET/.github/workflows/gates.yml'"
else
  say "  .github/workflows/gates.yml already exists, leaving it alone."
fi

say ""
say "Done. If this is a fresh clone elsewhere, run:"
say "  git config core.hooksPath .githooks"
say "Edit harness/harness.config to wire in this project's format, lint, typecheck, and test commands."
say "Nothing was committed."
