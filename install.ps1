# Installs this repo into ~/.claude (or -Target) as LIVE links, so a later
# `git pull` here updates every device that ran this. See docs/INSTALL.md.
#
# Usage:
#   install.ps1 [-Target <dir>] [-DryRun] [-Update] [-Profile <name>] [-Yes]
#
# -Target   Where to install. Default: $HOME/.claude.
# -DryRun   Print what would happen. Change nothing. Does NOT suppress the
#           profile question below; only the actual install.
# -Update   Re-copy any file that had to fall back to a plain copy (because a
#           symlink could not be created without admin rights or Developer
#           Mode), so it picks up the latest content from the repo. A no-op
#           for anything that is a real link already. Does not affect which
#           profile is used (see -Profile below) -- it only controls whether
#           a fallback COPY gets refreshed.
# -Profile  <max|standard|lite>: picks which profiles/*.json sets the model
#           and effort rendered into the agent roles (see
#           profiles/lib/profile.ps1). Left out entirely: a plain re-run
#           always keeps whatever profile is ALREADY recorded at
#           <Target>/claude-setup-profile.json, silently, whether or not
#           -Update is given -- only an explicit -Profile ever switches it.
#           On a FIRST-TIME install (no record yet) running with a real
#           console on stdin, it asks which plan to use instead; -Update
#           does not change that either.
# -Yes      Skip that first-time question and use "max", the same silent
#           default a script or CI run already gets (stdin redirected)
#           without needing this flag at all.
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
#
# -Profile <max|standard|lite> picks which profiles/*.json sets the model
# and effort rendered into the agent roles (see profiles/lib/profile.ps1).
# Left out: a plain re-run keeps whatever profile is already recorded at
# <Target>/claude-setup-profile.json, silently, regardless of -Update --
# -Update only ever controls whether a fallback copy gets refreshed, never
# which profile is active. Only an explicit -Profile ever switches an
# existing install to a different profile. With no record at all (a
# first-time install) running interactively, it asks (see below). -Yes
# forces the no-record default (max) instead of asking, for a scripted
# first-time install.
# Note: this shadows the automatic $PROFILE variable for the rest of this
# script; nothing here needs that variable.
param(
    [string]$Target = (Join-Path $HOME ".claude"),
    [switch]$DryRun,
    [switch]$Update,
    [string]$Profile,
    [switch]$Yes
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# CLAUDE_SETUP_TEST_STAMP overrides the real clock -- test-only, used to
# force two separate runs to collide on the same stamp deterministically
# (see Ensure-BackupDir below for why that case needs its own handling)
# instead of needing to win a real race against the wall clock.
$stamp = if ($env:CLAUDE_SETUP_TEST_STAMP) { $env:CLAUDE_SETUP_TEST_STAMP } else { [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ") }
# $backupRoot/$script:backupDirName are resolved lazily, by Ensure-BackupDir,
# the first time this run actually needs to back something up -- not here,
# where $stamp alone (one-second resolution) could collide with a SEPARATE
# run's folder started in the same second (two installs back to back, or a
# profile switch run right after an install). See Ensure-BackupDir.
$backupRoot = $null
$script:backupDirName = $null
$script:backedUp = $false

function Say($msg) { Write-Host $msg }

. (Join-Path $here "profiles/lib/profile.ps1")

# Test-ProfileInteractive -- true only when this run has both a real
# console (not e.g. a service host) AND stdin is not redirected (a file
# or a pipe). Both checks matter: UserInteractive alone is still true when
# stdin was redirected from a file, which would otherwise try to prompt
# against input that was never meant to answer it.
function Test-ProfileInteractive {
    try {
        return [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)
    } catch {
        return $false
    }
}

$profilesDir = Join-Path $here "profiles"
$recordPath = Join-Path $Target "claude-setup-profile.json"
$profileExplicit = $PSBoundParameters.ContainsKey('Profile')
$validProfileNames = Get-ProfileValidNames $profilesDir
$recordExists = Test-Path $recordPath
# An explicit -Profile is the user's own stated intent: refresh every
# profile-derived file (agents, settings.json) to match, with no -Update
# needed, whether or not it happens to equal what is already recorded.
$profileSwitch = $profileExplicit

if ($profileExplicit) {
    $chosenProfileName = $Profile
} elseif ($recordExists) {
    # A plain re-run (no -Profile) ALWAYS keeps whatever is already
    # recorded, with or without -Update: -Update only controls whether a
    # fallback copy gets refreshed, never which profile is active.
    $chosenProfileName = $null
    try {
        $rec = Get-Content -Path $recordPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($rec.name) { $chosenProfileName = $rec.name }
    } catch {}
    if (-not $chosenProfileName) {
        Write-Host "Could not read a profile name from $recordPath. Pass -Profile explicitly."
        exit 1
    }
} elseif ((-not $Yes) -and (Test-ProfileInteractive)) {
    # First-time install, asked for explicitly: no -Profile, nothing
    # recorded yet, an interactive session, and -Yes was not given to
    # force the quiet default. -DryRun does NOT suppress this: the point
    # of -DryRun is exploring what a real run would do, and a real run
    # would ask here too.
    $menuOrder = Get-ProfileMenuOrder $validProfileNames
    $chosenProfileName = Read-ProfileChoice $profilesDir $menuOrder
    if (-not $chosenProfileName) {
        Write-Host "No valid profile chosen after 3 attempts. Nothing was installed."
        exit 1
    }
} else {
    # No -Profile, no record, and (non-interactive OR -Yes): there is
    # no safe default to fall back on, so this stops here, before
    # changing anything, rather than silently installing "max" -- a
    # friend on a cheap plan running this non-interactively (an AI
    # assistant acting on their behalf, say) would otherwise end up on
    # the HEAVIEST profile instead of the lightest, the exact opposite
    # of what "no answer" should ever mean.
    $targetArgForMessage = if ($PSBoundParameters.ContainsKey('Target')) { $Target } else { "" }
    Write-ProfileRequiredMessage $profilesDir (Get-ProfileMenuOrder $validProfileNames) $Yes.IsPresent $targetArgForMessage
    exit 1
}

if ($validProfileNames -notcontains $chosenProfileName) {
    Write-Host "Unknown profile '$chosenProfileName'. Valid profiles: $($validProfileNames -join ', ')"
    exit 1
}

$chosenProfilePath = Join-Path $profilesDir "$chosenProfileName.json"
$profileCheck = Test-ProfileValid $chosenProfilePath
if (-not $profileCheck.Valid) {
    Write-Host "Profile '$chosenProfileName' failed validation: $($profileCheck.Error)"
    exit 1
}
$activeProfile = $profileCheck.Profile
$profileBuildAgents = Join-Path $here ".profile-build/$chosenProfileName/agents"
$globalSettingsPath = Join-Path $here "global/settings.json"

if ($chosenProfileName -eq "max") {
    # max links agents/ and settings.json straight from the repo,
    # unchanged -- nothing else enforces that max.json's own values
    # still match them, so check by hand rather than silently installing
    # from the (correct) files while printing a changed "->" value from
    # max.json that was never actually applied.
    $maxConsistency = Test-MaxProfileConsistency $activeProfile (Join-Path $here "agents") $globalSettingsPath
    if (-not $maxConsistency.Valid) {
        Write-Host "Profile 'max' is out of sync: $($maxConsistency.Error)"
        exit 1
    }
    $settingsSource = $globalSettingsPath
} else {
    $settingsSource = Join-Path $here ".profile-build/$chosenProfileName/settings.json"
}

# The 3-line summary, right after the profile is settled (by flag,
# record, prompt, or default) and validated, before anything is linked,
# rendered, or written. The main-session line moves to AFTER settings.json
# is actually installed (see the bottom of this script): "applied" must
# never be said until the file on disk has been read back and confirmed
# to carry these values.
Say ""
Say "Profile: $chosenProfileName"
Say "Workflow mode: $($activeProfile.workflowMode)"
Say "Max parallel teammates: $($activeProfile.maxParallelTeammates)"

function Get-Sha256($path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

# Resolves a backup folder name this run, and only this run, owns: the
# stamp alone (one-second resolution) is not enough -- two installs back
# to back (or a profile switch run right after an install) can land in
# the same second, and sharing one folder meant the second run's
# Move-Item either nested a junction INSIDE the first run's backed-up
# original, or silently overwrote it outright, permanently losing the
# user's own file. Stamp + PID resolves that in practice; the -2, -3...
# loop is the fallback for the one case PID alone cannot rule out (PID
# reuse hitting the exact same stamp).
function Ensure-BackupDir {
    if (-not $script:backedUp) {
        $base = "claude-setup-$stamp-$PID"
        $candidate = $base
        $n = 2
        while (Test-Path (Join-Path $Target "backups/$candidate")) {
            $candidate = "$base-$n"
            $n++
        }
        $script:backupDirName = $candidate
        $script:backupRoot = Join-Path $Target "backups/$candidate"
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $script:backupRoot | Out-Null }
        $script:backedUp = $true
    }
}

# Backup-Existing <path> <relName> -- moves existing content aside and
# returns the backup folder name ("claude-setup-<UTC>-<PID>[-N]") the
# caller should record in the manifest, or $null if there was nothing to
# back up. Never moves onto an existing destination: Ensure-BackupDir
# already guarantees this run owns a fresh backup folder no other run
# has touched, so $dest existing here would mean something else is
# wrong (the same relName backed up twice in one run); failing loudly
# before touching anything is safer than a silent overwrite either way.
function Backup-Existing($path, $relName) {
    if (-not (Test-Path $path)) { return $null }
    Ensure-BackupDir
    $dest = Join-Path $backupRoot $relName
    if (Test-Path $dest) {
        Write-Host "claude-setup: refusing to overwrite an existing backup at $dest. This should not happen; please report it. '$relName' itself was NOT moved or touched -- but this run is not atomic, so any path already linked, copied, or backed up earlier in THIS SAME run is already done; re-run once the cause is fixed to pick up where this stopped."
        exit 1
    }
    if ($DryRun) {
        Say "  (dry run) back up $relName"
        return $script:backupDirName
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Move-Item -Path $path -Destination $dest -Force
    Say "  backed up $relName -> $dest"
    return $script:backupDirName
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
    if (-not $kind) {
        # No manifest line at all: this is the FIRST time this path is
        # taken over, so back up whatever is really there (possibly
        # nothing; Backup-Existing then correctly leaves $backupRef empty).
        # Checking $kind rather than $backupRef matters once a profile can
        # point "agents" at a different source between runs (see
        # Get-ProfileAgentsSource): $backupRef is legitimately "" whenever
        # there was truly nothing to back up, and that empty STRING must
        # not be mistaken for "no manifest line yet" on a later run, or a
        # profile switch would wrongly back up our OWN prior content as if
        # it were the pre-claude-setup original, and uninstall would later
        # restore that stale content instead of leaving the path empty.
        $backupRef = Backup-Existing $dest $relName
    } elseif ((Test-Path $dest) -or (Get-Item $dest -Force -ErrorAction SilentlyContinue)) {
        # We already own this path (a manifest line is on file from the
        # first takeover). What is here now is either our own stale link
        # (safe to discard, we can always re-link it, including to a
        # different source on a profile switch) or something that REPLACED
        # our link with real content since -- a user's own directory, or a
        # tool that saves over a symlink by write-then-rename. That content
        # is not necessarily disposable, so it goes into THIS run's backup
        # folder instead of being deleted; $backupRef keeps pointing at the
        # ORIGINAL pre-claude-setup content either way, since that is what
        # uninstall should restore.
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

# Link-File -- the $forceRefresh parameter refreshes an unmodified copy
# even without -Update, the same way -Update would -- used by
# Install-Settings when an explicit profile switch is the reason this
# file needs to change now (a hand-edited copy is still left alone
# either way; that check runs first, below).
function Link-File($relName, $source, [bool]$forceRefresh = $false) {
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
        if (-not $Update -and -not $forceRefresh) {
            Say "  $relName is already installed as a copy, leaving it. Use -Update to refresh it."
            return
        }
        # -Update, or an explicit profile switch, on our own, unmodified
        # copy: refresh in place, no new backup -- the real original is
        # already preserved under backupRef from the first takeover.
        if ($DryRun) {
            Say "  (dry run) refresh copy of $relName"
            return
        }
        Copy-Item $source $dest -Force
        Set-Manifest $relName "copy" $backupRef (Get-Sha256 $dest)
        if ($Update) {
            Say "  refreshed copy of $relName (-Update)"
        } else {
            Say "  refreshed copy of $relName (profile switch)"
        }
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

# Test-ProfileSwitchConflict -- checked ONCE, up front, before anything
# is linked, rendered, or written, whenever this run is an explicit
# profile switch (see $profileSwitch above). If settings.json is already
# installed as a copy and its checksum no longer matches what claude-setup
# itself last wrote there (a hand edit), the WHOLE run stops here: a
# hand-edited copy is never silently overwritten by a switch, and
# "before changing anything" means literally nothing changes this run,
# not even the profile record, rather than aborting partway through with
# some paths already moved and others not.
function Test-ProfileSwitchConflict($settingsDest) {
    $kind = Get-ManifestField "settings.json" 1
    if ($kind -eq "copy" -and (Test-Path $settingsDest)) {
        $curSum = Get-Sha256 $settingsDest
        $checksum = Get-ManifestField "settings.json" 3
        if ($curSum -ne $checksum) {
            return "settings.json was edited since claude-setup wrote it as a copy. Refusing to switch profiles until that is resolved by hand: restore claude-setup's copy (then re-run), or do not pass -Profile if you want to keep your edit."
        }
    }
    return $null
}

# Write-SettingsKeyDiff <dest> <source> -- prints which top-level keys of
# the user's own settings.json (if any already exists there, unmanaged)
# would be added, removed, or changed by installing $source over it.
# Shared by Install-Settings (max) and Install-ProfileSettings
# (standard/lite): a friend on the cheapest plan needs this just as much
# as a max install does -- it is the only way the assistant running
# SETUP-WITH-CLAUDE.md can point out which of the user's own permissions,
# env vars, or hooks stop applying while this is installed.
function Write-SettingsKeyDiff($dest, $source) {
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

function Install-Settings($source, [bool]$forceRefresh = $false) {
    $relName = "settings.json"
    $dest = Join-Path $Target $relName
    $alreadyManaged = [bool](Get-ManifestField $relName 1)
    if ((Test-Path $dest) -and -not $alreadyManaged -and -not (Test-PointsAt $dest $source)) {
        Write-SettingsKeyDiff $dest $source
    }
    Link-File $relName $source $forceRefresh
}

# Install-ProfileSettings -- used for standard/lite instead of
# Install-Settings/Link-File: settings.json is ALWAYS installed as a
# plain tracked COPY of the rendered file, checksum recorded, never a
# link into .profile-build/<profile>/. .profile-build is gitignored and
# meant to be deleted and regenerated; a symlink into it would leave
# settings.json (and every hook it wires, the git guard included)
# dangling the moment that happens, until the next -Update. agents may
# still link into .profile-build -- only settings.json gets this
# never-a-link treatment.
#
# $forceRefresh (an explicit profile switch, see $profileSwitch above)
# re-copies even without -Update, since the switch itself is the user's
# intent to make this file match NOW. A hand-edited copy is left alone
# either way; Test-ProfileSwitchConflict already refused the whole run
# before this is ever reached if a switch would have overwritten one.
function Install-ProfileSettings($source, [bool]$forceRefresh) {
    $relName = "settings.json"
    $dest = Join-Path $Target $relName
    $kind = Get-ManifestField $relName 1
    $backupRef = Get-ManifestField $relName 2
    $checksum = Get-ManifestField $relName 3

    if ($kind -eq "copy" -and (Test-Path $dest)) {
        $curSum = Get-Sha256 $dest
        if ($curSum -ne $checksum) {
            Say "  $relName was edited since claude-setup wrote it; leaving it alone (not overwriting your changes)."
            return
        }
        if (-not $forceRefresh -and -not $Update) {
            Say "  $relName is already installed as a copy of this profile's rendered settings, leaving it. Use -Update or -Profile to refresh it."
            return
        }
    } elseif ($kind -and (Test-Path $dest)) {
        # Was a LINK before (an earlier install, or a platform where a
        # file symlink actually succeeds); replacing it with our own copy
        # takes over a path a different mechanism owned, so back up what
        # is physically there first -- same discipline Link-Dir uses when
        # a link gets replaced by something else.
        Backup-Existing $dest $relName | Out-Null
    }

    if (-not $kind) {
        if (Test-Path $dest) {
            Write-SettingsKeyDiff $dest $source
        }
        $backupRef = Backup-Existing $dest $relName
    }
    if ($DryRun) {
        Say "  (dry run) copy $relName <- $source"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item $source $dest -Force
    Set-Manifest $relName "copy" $backupRef (Get-Sha256 $dest)
    Say "  copied $relName <- $source (tracked copy, never a link into .profile-build)"
}

# Write-ProfileRecord -- copies the chosen profile's own JSON, byte for
# byte, to <Target>/claude-setup-profile.json: a plain file this installer
# owns outright (never a symlink, since each install target can pick its
# own profile), always rewritten to match THIS run's choice. The "already
# managed" check mirrors Install-Settings' own: a manifest line's kind is
# never empty once written, so this only backs up pre-existing foreign
# content the very first time, exactly like every other managed path.
#
# $forceRefresh (an explicit profile switch) treats a hand-edited record
# differently from every other hand-edited copy: the switch is strong,
# explicit intent for THIS run's profile, so the edit is preserved in the
# backup folder (never silently lost) but the record still gets written,
# rather than left to fall out of step with the agents/settings links
# this same run just moved: a hand-edited record surviving a switch
# would otherwise mean the NEXT plain re-run silently reverted to the
# old profile.
function Write-ProfileRecord($profileObj, $sourcePath, [bool]$forceRefresh) {
    $relName = "claude-setup-profile.json"
    $dest = Join-Path $Target $relName
    $kind = Get-ManifestField $relName 1
    $backupRef = Get-ManifestField $relName 2
    $checksum = Get-ManifestField $relName 3

    if ($kind -eq "copy" -and (Test-Path $dest)) {
        $curSum = Get-Sha256 $dest
        if ($curSum -ne $checksum) {
            if (-not $forceRefresh) {
                Say "  $relName was edited since claude-setup wrote it; leaving it alone (not overwriting your changes)."
                return
            }
            if ($DryRun) {
                Say "  (dry run) back up hand-edited $relName and write the new record"
            } else {
                Backup-Existing $dest $relName | Out-Null
            }
        }
    }

    if (-not $kind) {
        $backupRef = Backup-Existing $dest $relName
    }
    if ($DryRun) {
        Say "  (dry run) write profile record for '$($profileObj.name)' -> $relName"
        return
    }
    Copy-Item $sourcePath $dest -Force
    Set-Manifest $relName "copy" $backupRef (Get-Sha256 $dest)
    Say "  wrote profile record: $relName (profile '$($profileObj.name)')"
}

if ($profileSwitch) {
    $switchConflict = Test-ProfileSwitchConflict (Join-Path $Target "settings.json")
    if ($switchConflict) {
        Write-Host $switchConflict
        exit 1
    }
}

Say "Installing claude-setup into: $Target"
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }

# Render (or just diff, under -DryRun or for the max profile) the 7 agent
# files for the chosen profile. The max profile never writes a rendered
# copy at all; it links agents/ straight from the repo.
$agentsSource = if ($chosenProfileName -eq "max") { Join-Path $here "agents" } else { $profileBuildAgents }
$writeRender = (-not $DryRun) -and ($chosenProfileName -ne "max")
$renderChanges = Render-ProfileAgents $activeProfile (Join-Path $here "agents") $profileBuildAgents -DryRun:(-not $writeRender)

Say "Rendering for '$chosenProfileName' ($($activeProfile.description)):"
foreach ($c in $renderChanges) {
    if ($c.OldModel -eq $c.NewModel -and $c.OldEffort -eq $c.NewEffort) {
        Say "  $($c.Role): model=$($c.NewModel) effort=$($c.NewEffort) (unchanged)"
    } else {
        Say "  $($c.Role): model $($c.OldModel) -> $($c.NewModel), effort $($c.OldEffort) -> $($c.NewEffort)"
    }
}
Say ""

# Same temp-then-swap discipline as the agent render: a failure here
# (an unexpected settings.json shape) throws BEFORE anything is linked,
# leaving an earlier render (if any) at $settingsSource untouched.
if ($chosenProfileName -ne "max") {
    Render-ProfileSettings $activeProfile $globalSettingsPath $settingsSource -DryRun:$DryRun | Out-Null
}

# The repo itself, at a stable absolute path: everything else this repo
# ships (templates/, lessons/, harness/, docs/) is only reachable through
# this one link, since skills and commands cannot know ahead of time where
# a given machine cloned claude-setup to.
Link-Dir "claude-setup" $here

Link-File "CLAUDE.md" (Join-Path $here "global/CLAUDE.md")
if ($chosenProfileName -eq "max") {
    Install-Settings $settingsSource $profileSwitch
} else {
    Install-ProfileSettings $settingsSource $profileSwitch
}
Link-Dir "agents" $agentsSource
Write-ProfileRecord $activeProfile $chosenProfilePath $profileSwitch
Link-Dir "commands" (Join-Path $here "commands")
Link-Dir "hooks" (Join-Path $here "hooks")
Link-Dir "statusline" (Join-Path $here "global/statusline")

if (-not $DryRun) { New-Item -ItemType Directory -Force -Path (Join-Path $Target "skills") | Out-Null }
Get-ChildItem -Directory (Join-Path $here "skills") | ForEach-Object {
    Link-Dir "skills/$($_.Name)" $_.FullName
}

Say ""
# Never say "applied" on faith: read back whatever settings.json actually
# holds now and compare, so a left-alone hand-edited copy (or any other
# reason it did not get the profile's values) is reported honestly
# instead of claimed.
if ($DryRun) {
    Say "Main session (per the '$chosenProfileName' profile, if this were a real run): model=$($activeProfile.main.model), effortLevel=$($activeProfile.main.effortLevel)."
} else {
    $installedSettingsPath = Join-Path $Target "settings.json"
    $installedSettings = $null
    try {
        $installedSettings = Get-Content -Path $installedSettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {}
    $verified = $installedSettings -and
        ($installedSettings.model -eq $activeProfile.main.model) -and
        ($installedSettings.effortLevel -eq $activeProfile.main.effortLevel)
    if ($verified) {
        Say "Main session (per the '$chosenProfileName' profile): model=$($activeProfile.main.model), effortLevel=$($activeProfile.main.effortLevel) -- applied to settings.json."
    } else {
        $actualModel = if ($installedSettings) { $installedSettings.model } else { "?" }
        $actualEffort = if ($installedSettings) { $installedSettings.effortLevel } else { "?" }
        # Diagnose the real cause instead of guessing "hand-edited": check
        # the same checksum Link-File just checked, rather than assuming
        # the one reason that happens to be most common.
        if (-not $installedSettings) {
            $reason = "settings.json is missing or could not be read"
        } else {
            $curSum = Get-Sha256 $installedSettingsPath
            $recordedSum = Get-ManifestField "settings.json" 3
            if ($recordedSum -and $curSum -ne $recordedSum) {
                $reason = "it is a hand-edited copy; see the messages above for why"
            } else {
                $reason = "this run did not refresh it (no profile switch and no -Update); re-run with -Update or -Profile to pick up the profile's values"
            }
        }
        Say "Main session: settings.json currently has model=$actualModel, effortLevel=$actualEffort -- NOT yet the '$chosenProfileName' profile's model=$($activeProfile.main.model), effortLevel=$($activeProfile.main.effortLevel). Left as-is because $reason."
    }
}
Say ""
if ($script:backedUp) {
    if ($DryRun) { Say "(dry run) backups would be written to: $backupRoot" }
    else { Say "Backups written to: $backupRoot" }
}
Say "Repo reachable at: $(Join-Path $Target 'claude-setup')"
Say "Profile record at: $(Join-Path $Target 'claude-setup-profile.json')"
Say "Never touched: .credentials.json, history.jsonl, projects/, sessions/, caches."
Say "Nothing was committed; this script never runs git."
Say "Done."
