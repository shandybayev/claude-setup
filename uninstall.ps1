# Removes the links/copies install.ps1 created and restores each one's own
# pre-claude-setup original, if it had one.
#
# Usage: uninstall.ps1 [-Target <dir>] [-DryRun]
#
# Driven ENTIRELY by the manifest (.claude-setup-installed) install.ps1
# writes. No fixed name list, and nothing it did not itself record is ever
# touched: a second uninstall run, or one on a target where install never
# ran, used to fall back to "anything at one of our well-known names that
# is not currently a link must be a copy of ours" and delete real user
# files that way. If there is no manifest, there is nothing recorded as
# installed here, so nothing is removed.
param(
    [string]$Target = (Join-Path $HOME ".claude"),
    [switch]$DryRun
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "profiles/lib/profile.ps1")

function Say($msg) { Write-Host $msg }

function Get-Sha256($path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

# Test-PointsAt -- see install.ps1's copy of this function for the full
# comment; kept identical so both scripts agree on what "still points into
# this repo" means.
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

# Get-RelSource <rel> -- the repo path a managed rel ought to point at, used
# as an independent check (beyond the manifest's say-so) that a "link" entry
# still really resolves into THIS repo before it gets deleted.
function Get-RelSource($rel) {
    switch -Regex ($rel) {
        '^claude-setup$' { return $here }
        '^CLAUDE\.md$' { return (Join-Path $here "global/CLAUDE.md") }
        # "agents" and "settings.json" can each point at the repo's own
        # file/folder (the max profile) or at that profile's own rendered
        # .profile-build/<name>/ (any other profile); which one depends on
        # the profile recorded for THIS target, not a fixed path, so both
        # are resolved the same way install.ps1 resolved them. settings.json
        # is installed as a plain copy for every non-max profile now, so
        # this mainly matters if settings.json is somehow still a link at
        # that path (a manual edit, or a manifest line never refreshed).
        '^agents$' { return $script:ResolvedAgentsSource }
        '^settings\.json$' { return $script:ResolvedSettingsSource }
        '^commands$' { return (Join-Path $here "commands") }
        '^hooks$' { return (Join-Path $here "hooks") }
        '^statusline$' { return (Join-Path $here "global/statusline") }
        '^skills/' { return (Join-Path $here $rel) }
        # claude-setup-profile.json is never a link (always a plain file
        # this installer wrote outright), so it has no "source" to compare
        # against; the "copy" branch below never looks at this anyway.
        '^claude-setup-profile\.json$' { return $null }
        default { return $null }
    }
}

$manifestPath = Join-Path $Target ".claude-setup-installed"
if (-not (Test-Path $manifestPath)) {
    Say "No install manifest at $manifestPath. Nothing was recorded as installed by claude-setup here, so nothing will be removed."
    exit 0
}

# Resolved once, up front, from whatever profile is on record right now --
# not re-read per manifest line. The manifest's lines are appended in
# whatever order they were last (re)written in, which need not put
# "agents" before "claude-setup-profile.json"; reading the record fresh
# per line could see it already deleted by the time "agents" is reached,
# and silently fall back to the wrong (max) source.
$script:ResolvedAgentsSource = Get-ProfileAgentsSource $here $Target
$script:ResolvedSettingsSource = Get-ProfileSettingsSource $here $Target

$backupsDir = Join-Path $Target "backups"
$lines = @(Get-Content $manifestPath)
$remainingLines = @()

foreach ($line in $lines) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split "`t"
    $rel = $parts[0]
    $kind = if ($parts.Length -gt 1) { $parts[1] } else { "" }
    $backupRef = if ($parts.Length -gt 2) { $parts[2] } else { "" }
    $checksum = if ($parts.Length -gt 3) { $parts[3] } else { "" }

    $path = Join-Path $Target $rel
    $source = Get-RelSource $rel
    $removed = $false
    $skip = $false

    switch ($kind) {
        "link" {
            if (-not (Test-Path $path)) {
                Say "  $rel is already gone."
                $removed = $true
            } elseif ($source -and -not (Test-PointsAt $path $source)) {
                Say "  $rel no longer points into this repo (something replaced it since install); leaving it alone. Remove it by hand if you want it gone."
                $skip = $true
            } else {
                if ($DryRun) {
                    Say "  (dry run) remove $rel (link)"
                } else {
                    Remove-Item $path -Force -Recurse -ErrorAction SilentlyContinue
                    Say "  removed $rel (link)"
                }
                $removed = $true
            }
        }
        "copy" {
            if (-not (Test-Path $path)) {
                Say "  $rel is already gone."
                $removed = $true
            } else {
                $curSum = if (Test-Path $path -PathType Leaf) { Get-Sha256 $path } else { "" }
                if ($checksum -and $curSum -ne $checksum) {
                    Say "  $rel was edited since claude-setup wrote it; leaving it alone so your changes are not lost."
                    $skip = $true
                } else {
                    if ($DryRun) {
                        Say "  (dry run) remove $rel (copy)"
                    } else {
                        Remove-Item $path -Force -Recurse -ErrorAction SilentlyContinue
                        Say "  removed $rel (copy)"
                    }
                    $removed = $true
                }
            }
        }
        default {
            Say "  $rel`: unrecognized manifest kind '$kind', leaving it alone."
            $skip = $true
        }
    }

    if ($skip) {
        $remainingLines += $line
        continue
    }

    if ($backupRef) {
        $backupPath = Join-Path $backupsDir "$backupRef/$rel"
        if (Test-Path $backupPath) {
            if ($DryRun) {
                Say "  (dry run) restore $rel from $backupRef"
            } else {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
                Move-Item -Path $backupPath -Destination $path -Force
                Say "  restored $rel from $backupRef"
            }
        }
    }
    # Processed (removed, or already gone): drop its manifest line. A
    # DryRun run does not actually touch the manifest file at all.
}

if (-not $DryRun) {
    if ($remainingLines) { Set-Content -Path $manifestPath -Value $remainingLines }
    else { Remove-Item $manifestPath -Force -ErrorAction SilentlyContinue }
}

Say ""
Say "Nothing outside what the manifest listed was touched. Nothing was committed."
Say "Done."
