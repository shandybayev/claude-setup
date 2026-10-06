# Installs this repo into ~/.claude (or -Target) as LIVE links, so a later
# `git pull` here updates every device that ran this. See docs/INSTALL.md.
#
# Usage:
#   install.ps1 [-Target <dir>] [-DryRun] [-Update]
#
# -Target   Where to install. Default: $HOME/.claude.
# -DryRun   Print what would happen. Change nothing.
# -Update   Re-copy any file that had to fall back to a plain copy (because a
#           symlink could not be created without admin rights or Developer
#           Mode), so it picks up the latest content from the repo. A no-op
#           for anything that is a real link already.
#
# What this does:
#   - links claude-setup itself at <Target>/claude-setup, so anything
#     installed can always find templates/, lessons/, harness/, docs/ by an
#     absolute, stable path, even from a different project directory;
#   - links CLAUDE.md and settings.json (files: symlink, or a copy + warning
#     if symlinks are not allowed here);
#   - links agents/, commands/, hooks/, and statusline/ as whole directories
#     (directory junctions: no admin needed on Windows);
#   - links EACH skill under skills/ individually, so any other skill the
#     target already has stays exactly where it is;
#   - backs up anything it is about to REPLACE into
#     <Target>/backups/claude-setup-<UTC timestamp>/, but only the FIRST
#     time a path is taken over: once a path is ours, a later run (including
#     -Update) never backs it up a second time, which used to strand the
#     user's real original behind a newer backup that only ever held our
#     own stale copy;
#   - NEVER touches .credentials.json, history.jsonl, projects/, sessions/,
#     or any cache directory. Those names never appear in the list above, so
#     there is nothing in this script that could reach them.
#   - never runs git, never commits, never pushes.
#
# A link already at the destination is only ever trusted as ours when its
# OWN .Target resolves into this repo (Test-PointsAt below), never merely
# because something link-shaped is already there: a user's own junction
# pointing somewhere else of theirs is backed up (as the link entity, which
# never touches what it pointed at) and replaced like any other pre-existing
# content.
param(
    [string]$Target = (Join-Path $HOME ".claude"),
    [switch]$DryRun,
    [switch]$Update
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$backupRoot = Join-Path $Target "backups/claude-setup-$stamp"
$script:backedUp = $false

function Say($msg) { Write-Host $msg }

function Get-Sha256($path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

function Ensure-BackupDir {
    if (-not $script:backedUp) {
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null }
        $script:backedUp = $true
    }
}

# Backup-Existing <path> <relName> -- moves existing content aside and
# returns the backup stamp ("claude-setup-<UTC>") the caller should record
# in the manifest, or $null if there was nothing to back up.
function Backup-Existing($path, $relName) {
    if (-not (Test-Path $path)) { return $null }
    Ensure-BackupDir
    $dest = Join-Path $backupRoot $relName
    if ($DryRun) {
        Say "  (dry run) back up $relName"
        return "claude-setup-$stamp"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Move-Item -Path $path -Destination $dest -Force
    Say "  backed up $relName -> $dest"
    return "claude-setup-$stamp"
}

# Test-PointsAt <path> <source> -- true only when path is a link/junction
# whose OWN target resolves to source. Replaces a bare "is this a link"
# check, which used to treat ANY existing link (including a user's own
# junction pointing at something else entirely) as already ours.
function Test-PointsAt($path, $source) {
    $item = Get-Item $path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.LinkType) { return $false }
    $t = $item.Target
    if ($t -is [array]) { $t = $t[0] }
    if (-not $t) { return $false }
    if (-not [System.IO.Path]::IsPathRooted($t)) {
        $t = Join-Path (Split-Path $path -Parent) $t
    }
    try { $t = (Resolve-Path -LiteralPath $t -ErrorAction Stop).Path } catch {}
    try { $src = (Resolve-Path -LiteralPath $source -ErrorAction Stop).Path } catch { $src = $source }
    return ($t.TrimEnd('\') -ieq $src.TrimEnd('\'))
}

# The manifest: one line per managed path, "rel<TAB>kind<TAB>backup_ref<TAB>
# checksum". kind is link or copy. backup_ref is the backup stamp that holds
# this path's pre-claude-setup original (empty if there was none). checksum
# is the sha256 of a copy-kind file as WE wrote it, used so a later run (and
# uninstall) can tell "our unmodified copy" from "the user edited this since
# we wrote it" before touching it again.
#
# install.sh writes the exact same format, so the two scripts agree on one
# manifest regardless of which one a user runs on a given machine.
$ManifestPath = Join-Path $Target ".claude-setup-installed"

function Get-ManifestLine($relName) {
    if (-not (Test-Path $ManifestPath)) { return $null }
    (Get-Content $ManifestPath) | Where-Object { $_ -match "^$([regex]::Escape($relName))\t" } | Select-Object -Last 1
}
function Get-ManifestField($relName, $index) {
    $line = Get-ManifestLine $relName
    if (-not $line) { return "" }
    $parts = $line -split "`t"
    if ($parts.Length -gt $index) { return $parts[$index] } else { return "" }
}

function Set-Manifest($relName, $kind, $backupRef, $checksum) {
    if ($DryRun) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ManifestPath) | Out-Null
    $lines = @()
    if (Test-Path $ManifestPath) {
        # The extra @(...) around the WHOLE pipeline is load-bearing: when
        # Where-Object's result is exactly one line, PowerShell hands back a
        # bare string instead of a one-element array, and the later +=
        # below would silently do STRING concatenation (no separator, no
        # newline) instead of an array append, corrupting every line after
        # the first into one unparseable run-on line.
        $lines = @(@(Get-Content $ManifestPath) | Where-Object { $_ -notmatch "^$([regex]::Escape($relName))\t" })
    }
    $lines += "$relName`t$kind`t$backupRef`t$checksum"
    Set-Content -Path $ManifestPath -Value $lines
}

function Link-Dir($relName, $source) {
    $dest = Join-Path $Target $relName
    $kind = Get-ManifestField $relName 1

    if ((Test-Path $dest) -and (Test-PointsAt $dest $source)) {
        Say "  $relName already links to the repo, skipping."
        return
    }

    $backupRef = Get-ManifestField $relName 2
    if (-not $backupRef) {
        $backupRef = Backup-Existing $dest $relName
    } elseif ((Test-Path $dest) -or (Get-Item $dest -Force -ErrorAction SilentlyContinue)) {
        # We already own this path (its backup_ref is on file from the
        # first takeover). What is here now is either our own stale link
        # (safe to discard, we can always re-link it) or something that
        # REPLACED our link with real content since -- a user's own
        # directory, or a tool that saves over a symlink by write-then-
        # rename. That content is not necessarily disposable, so it goes
        # into THIS run's backup folder instead of being deleted; $backupRef
        # keeps pointing at the ORIGINAL pre-claude-setup content either
        # way, since that is what uninstall should restore.
        Backup-Existing $dest $relName | Out-Null
    }

    if ($DryRun) {
        Say "  (dry run) link $relName -> $source"
        return
    }

    if (Test-Path $dest) { Remove-Item $dest -Force -Recurse -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    try {
        New-Item -ItemType Junction -Path $dest -Target $source -ErrorAction Stop | Out-Null
        Set-Manifest $relName "link" $backupRef ""
        Say "  linked $relName -> $source (junction)"
    } catch {
        if (Test-Path $dest) { Remove-Item $dest -Force -Recurse -ErrorAction SilentlyContinue }
        Copy-Item $source $dest -Recurse -Force
        Set-Manifest $relName "copy" $backupRef ""
        Say "  WARNING: could not create a junction for $relName. Copied instead; re-run with -Update after a git pull to refresh it."
    }
}

function Link-File($relName, $source) {
    $dest = Join-Path $Target $relName
    $kind = Get-ManifestField $relName 1
    $backupRef = Get-ManifestField $relName 2

    if ($kind -eq "link" -and (Test-Path $dest) -and (Test-PointsAt $dest $source)) {
        Say "  $relName already links to the repo, skipping."
        return
    }

    if ($kind -eq "copy" -and (Test-Path $dest)) {
        $curSum = Get-Sha256 $dest
        if ($curSum -ne (Get-ManifestField $relName 3)) {
            Say "  $relName was edited since claude-setup wrote it; leaving it alone (not overwriting your changes)."
            return
        }
        if (-not $Update) {
            Say "  $relName is already installed as a copy, leaving it. Use -Update to refresh it."
            return
        }
        # -Update on our own, unmodified copy: refresh in place, no new
        # backup -- the real original is already preserved under
        # backupRef from the first takeover.
        if ($DryRun) {
            Say "  (dry run) refresh copy of $relName"
            return
        }
        Copy-Item $source $dest -Force
        Set-Manifest $relName "copy" $backupRef (Get-Sha256 $dest)
        Say "  refreshed copy of $relName (-Update)"
        return
    }

    if (-not $backupRef) {
        $backupRef = Backup-Existing $dest $relName
    } elseif ((Test-Path $dest) -or (Get-Item $dest -Force -ErrorAction SilentlyContinue)) {
        # See Link-Dir's matching comment: this path is already ours, but
        # what is here now does not match the repo (kind=link with
        # mismatched content, since the kind=copy case above already
        # returned). Preserve it in this run's backup rather than deleting
        # it; backupRef keeps pointing at the real pre-claude-setup original.
        Backup-Existing $dest $relName | Out-Null
    }

    if ($DryRun) {
        Say "  (dry run) link $relName -> $source"
        return
    }

    if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path $dest -Target $source -ErrorAction Stop | Out-Null
        Set-Manifest $relName "link" $backupRef ""
        Say "  linked $relName -> $source (symlink)"
    } catch {
        if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
        Copy-Item $source $dest -Force
        Set-Manifest $relName "copy" $backupRef (Get-Sha256 $dest)
        Say "  WARNING: could not create a symlink for $relName (needs admin rights or Developer Mode on Windows). Copied instead; re-run with -Update after a git pull to refresh it."
    }
}

function Install-Settings {
    $relName = "settings.json"
    $dest = Join-Path $Target $relName
    $source = Join-Path $here "global/settings.json"
    $alreadyManaged = [bool](Get-ManifestField $relName 1)
    if ((Test-Path $dest) -and -not $alreadyManaged -and -not (Test-PointsAt $dest $source)) {
        try {
            $existing = Get-Content $dest -Raw | ConvertFrom-Json
            $incoming = Get-Content $source -Raw | ConvertFrom-Json
            $existingKeys = @($existing.PSObject.Properties.Name)
            $incomingKeys = @($incoming.PSObject.Properties.Name)
            $added = $incomingKeys | Where-Object { $_ -notin $existingKeys }
            $removed = $existingKeys | Where-Object { $_ -notin $incomingKeys }
            $common = $incomingKeys | Where-Object { $_ -in $existingKeys }
            $changed = $common | Where-Object {
                (ConvertTo-Json $existing.$_ -Depth 10 -Compress) -ne (ConvertTo-Json $incoming.$_ -Depth 10 -Compress)
            }
            Say ("  settings.json keys -- added: [{0}]  removed: [{1}]  changed: [{2}]" -f
                ($added -join ", "), ($removed -join ", "), ($changed -join ", "))
        } catch {
            Say "  settings.json: could not parse the existing file to diff keys; backing it up as usual."
        }
    }
    Link-File $relName $source
}

Say "Installing claude-setup into: $Target"
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }

# The repo itself, at a stable absolute path: everything else this repo
# ships (templates/, lessons/, harness/, docs/) is only reachable through
# this one link, since skills and commands cannot know ahead of time where
# a given machine cloned claude-setup to.
Link-Dir "claude-setup" $here

Link-File "CLAUDE.md" (Join-Path $here "global/CLAUDE.md")
Install-Settings
Link-Dir "agents" (Join-Path $here "agents")
Link-Dir "commands" (Join-Path $here "commands")
Link-Dir "hooks" (Join-Path $here "hooks")
Link-Dir "statusline" (Join-Path $here "global/statusline")

if (-not $DryRun) { New-Item -ItemType Directory -Force -Path (Join-Path $Target "skills") | Out-Null }
Get-ChildItem -Directory (Join-Path $here "skills") | ForEach-Object {
    Link-Dir "skills/$($_.Name)" $_.FullName
}

Say ""
if ($script:backedUp) {
    if ($DryRun) { Say "(dry run) backups would be written to: $backupRoot" }
    else { Say "Backups written to: $backupRoot" }
}
Say "Repo reachable at: $(Join-Path $Target 'claude-setup')"
Say "Never touched: .credentials.json, history.jsonl, projects/, sessions/, caches."
Say "Nothing was committed; this script never runs git."
Say "Done."
