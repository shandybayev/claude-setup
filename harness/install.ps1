# Wires the harness into a project (Windows). Mirrors install.sh exactly;
# see harness/README.md for the contract. Never commits anything.
#
# Usage:
#   harness\install.ps1 [-Target <dir>] [-DryRun]
#   harness\install.ps1 -Verify [-Target <dir>]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$DryRun,
    [switch]$Verify
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$kitRoot = Split-Path -Parent $here

function Say($msg) { Write-Host $msg }

# Writes text as UTF-8 with NO byte-order mark. PowerShell 5.1's own
# "-Encoding utf8" (on Set-Content/Out-File) always writes a BOM, which a
# shebang line cannot tolerate: `#!/usr/bin/env bash` preceded by EF BB BF is
# not `#!` anymore as far as the kernel/git's hook runner is concerned, and
# the hook fails with "Exec format error" on every commit. $Content is
# normalized to LF-only first, since a literal `\r\n` in the source string
# would otherwise survive untouched.
function Set-Utf8NoBom([string]$Path, [string]$Content) {
    $lf = $Content -replace "`r`n", "`n"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $lf, $encoding)
}

# Finds a real Git-for-Windows bash, not the System32 WSL-launcher stub that
# can win a plain PATH search and fails at exec time when WSL is not set up.
function Find-RealBash {
    foreach ($candidate in @("C:\Program Files\Git\bin\bash.exe", "C:\Program Files\Git\usr\bin\bash.exe")) {
        if (Test-Path $candidate) { return $candidate }
    }
    return (Get-Command bash.exe -ErrorAction SilentlyContinue).Source
}

function Invoke-Step($desc, [scriptblock]$action) {
    if ($DryRun) {
        Say "  (dry run) $desc"
    } else {
        Say "  $desc"
        & $action
    }
}

if ($Verify) {
    Push-Location $Target
    try {
        $ok = $true
        function Check($label, [scriptblock]$test) {
            if (& $test) { Say "OK   $label" } else { Say "FAIL $label"; $script:ok = $false }
        }

        # A hook file existing at this path proves nothing on its own: M5
        # showed install.ps1 could write one with a BOM, which Test-Path
        # calls fine and git refuses to run. Check the actual bytes.
        function Test-HookRunnable($path) {
            # Resolve to an absolute path through PowerShell's own location
            # first: raw .NET file I/O reads against the PROCESS's current
            # directory, which Push-Location does not keep in sync, so a
            # relative path here would silently read from the wrong place.
            $resolved = Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue
            if (-not $resolved) { return $false }
            $bytes = [System.IO.File]::ReadAllBytes($resolved.Path)
            if ($bytes.Length -lt 2) { return $false }
            return ($bytes[0] -eq 0x23 -and $bytes[1] -eq 0x21) # "#!"
        }

        Check "git on PATH" { [bool](Get-Command git -ErrorAction SilentlyContinue) }
        Check "bash on PATH" { [bool](Find-RealBash) }
        Check "core.hooksPath is .githooks" {
            (git config --get core.hooksPath 2>$null) -eq ".githooks"
        }
        Check ".githooks/pre-commit starts with #! (no BOM)" { Test-HookRunnable ".githooks/pre-commit" }
        Check ".githooks/pre-push starts with #! (no BOM)" { Test-HookRunnable ".githooks/pre-push" }
        Check ".githooks/commit-msg starts with #! (no BOM)" { Test-HookRunnable ".githooks/commit-msg" }
        Check "harness/gates.sh exists" { Test-Path "harness/gates.sh" }
        Check "harness/edit-check.sh exists" { Test-Path "harness/edit-check.sh" }
        Check "the PostToolUse edit-check hook is wired in .claude/settings.json" {
            $p = ".claude/settings.json"
            if (-not (Test-Path $p)) { return $false }
            try { $d = (Get-Content $p -Raw) | ConvertFrom-Json } catch { return $false }
            if (-not $d.hooks.PostToolUse) { return $false }
            foreach ($h in @($d.hooks.PostToolUse)) {
                if ($h.matcher -eq "Edit|Write") {
                    foreach ($c in @($h.hooks)) {
                        if ($c.command -like "*harness/edit-check.sh*") { return $true }
                    }
                }
            }
            return $false
        }
        # The project's own configured commands, not just the harness
        # scripts: the brief asked for "the tools on PATH", and a gate that
        # silently no-ops because FORMAT_CMD names a tool nobody installed
        # is a false sense of security.
        $cfgPath = "harness/harness.config"
        if (Test-Path $cfgPath) {
            foreach ($key in @("FORMAT_CMD", "LINT_CMD", "TYPECHECK_CMD", "TEST_CMD")) {
                $line = (Get-Content $cfgPath | Where-Object { $_ -match "^$key=" } | Select-Object -Last 1)
                if ($line) {
                    $cmd = ($line -split "=", 2)[1]
                    if ($cmd.Trim()) {
                        $tool = ($cmd.Trim() -split '\s+')[0]
                        Check "$key's tool ('$tool') is on PATH" { [bool](Get-Command $tool -ErrorAction SilentlyContinue) }
                    }
                }
            }
        }
        if ($ok) { Say "harness -Verify: all checks passed."; exit 0 }
        else { Say "x harness -Verify: one or more checks failed."; exit 1 }
    } finally {
        Pop-Location
    }
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null
Push-Location $Target
try {
    Say "Installing the harness into: $Target"

    Invoke-Step "copy harness/ scripts" {
        New-Item -ItemType Directory -Force -Path "$Target/harness/lib" | Out-Null
        foreach ($f in @("gates.sh", "gates.ps1", "edit-check.sh", "harness.config.example")) {
            Copy-Item "$kitRoot/harness/$f" "$Target/harness/$f" -Force
        }
        Copy-Item "$kitRoot/harness/lib/scope.sh" "$Target/harness/lib/scope.sh" -Force
    }

    if (-not (Test-Path "$Target/harness/harness.config")) {
        Invoke-Step "write harness/harness.config (from the example)" {
            Copy-Item "$kitRoot/harness/harness.config.example" "$Target/harness/harness.config"
        }
    } else {
        Say "  harness/harness.config already exists, leaving it alone."
    }

    Invoke-Step "create .githooks/" {
        New-Item -ItemType Directory -Force -Path "$Target/.githooks" | Out-Null
    }

    function Write-Hook($name, $body) {
        if ($DryRun) {
            Say "  (dry run) write .githooks/$name"
            return
        }
        $path = "$Target/.githooks/$name"
        Set-Utf8NoBom -Path $path -Content $body
        Say "  write .githooks/$name"
    }

    Write-Hook "pre-commit" "#!/usr/bin/env bash`nexec bash `"`$(git rev-parse --show-toplevel)/harness/gates.sh`" commit`n"
    Write-Hook "pre-push" "#!/usr/bin/env bash`nexec bash `"`$(git rev-parse --show-toplevel)/harness/gates.sh`" push`n"
    Write-Hook "commit-msg" "#!/usr/bin/env bash`nexec bash `"`$(git rev-parse --show-toplevel)/harness/gates.sh`" commit-msg `"`$1`"`n"

    if (-not $DryRun -and (Test-Path "$Target/.git")) {
        Invoke-Step "set core.hooksPath to .githooks" { git config core.hooksPath .githooks }
    } else {
        Say "  (dry run or no .git here) skipping: git config core.hooksPath .githooks"
    }

    # .gitattributes: force LF on the scripts and hooks this kit ships, so
    # a commit made on Windows (no execute bit either way, and CRLF if the
    # committer's git core.autocrlf mangled it) still runs on Mac/Linux/CI.
    # Idempotent: a line already present (exact match) is never duplicated,
    # and an existing file's other lines are kept. Set-Utf8NoBom guarantees
    # no BOM; every line is joined with a bare "`n" so the file is LF-only
    # even though this is PowerShell.
    $gaPath = "$Target/.gitattributes"
    $gaWanted = @('*.sh text eol=lf', '.githooks/* text eol=lf', 'harness/** text eol=lf')
    $gaExisting = @()
    if (Test-Path $gaPath) {
        # The extra @(...) around the whole pipeline is load-bearing (see
        # Set-Manifest's identical comment elsewhere in this file): a
        # single-line match collapses to a bare string, not a one-element
        # array, and later array operations on it would silently misbehave.
        $gaExisting = @(@(Get-Content $gaPath) | Where-Object { $_ -ne $null })
    }
    $gaToAdd = @($gaWanted | Where-Object { $gaExisting -notcontains $_ })
    foreach ($line in $gaWanted) {
        if ($gaExisting -contains $line) {
            Say "  .gitattributes already has: $line"
        } elseif ($DryRun) {
            Say "  (dry run) add to .gitattributes: $line"
        } else {
            Say "  added to .gitattributes: $line"
        }
    }
    if (-not $DryRun -and @($gaToAdd).Count -gt 0) {
        $gaFinal = @($gaExisting) + @($gaToAdd)
        Set-Utf8NoBom -Path $gaPath -Content (($gaFinal -join "`n") + "`n")
    }

    if (-not $DryRun) {
        # PowerShell 5.1's ConvertFrom-Json has no -AsHashtable, so this works
        # on the PSCustomObject it returns instead: Add-Member for a missing
        # property, direct assignment for one that already exists.
        $settingsPath = "$Target/.claude/settings.json"
        New-Item -ItemType Directory -Force -Path "$Target/.claude" | Out-Null
        $data = $null
        $parseFailed = $false
        if (Test-Path $settingsPath) {
            $raw = Get-Content $settingsPath -Raw
            if ($raw.Trim()) {
                try { $data = $raw | ConvertFrom-Json } catch { $parseFailed = $true }
            }
        }
        if ($parseFailed) {
            # The file exists and has content, it just did not parse (a
            # trailing comma, a hand edit). Overwriting it with a blank
            # object holding only our hook would silently destroy whatever
            # was there. Stop and say so instead; the python/node path in
            # install.sh already does this (it raises), so this matches.
            Say "  WARNING: .claude/settings.json exists but is not valid JSON. Leaving it untouched; add the PostToolUse hook by hand (see harness/README.md) after fixing it."
        } else {
        if (-not $data) { $data = New-Object PSObject }

        if (-not (Get-Member -InputObject $data -Name "hooks" -MemberType NoteProperty)) {
            $data | Add-Member -MemberType NoteProperty -Name "hooks" -Value (New-Object PSObject)
        }
        $hooksNode = $data.hooks
        if (-not (Get-Member -InputObject $hooksNode -Name "PostToolUse" -MemberType NoteProperty)) {
            $hooksNode | Add-Member -MemberType NoteProperty -Name "PostToolUse" -Value @()
        }

        $already = $false
        foreach ($h in @($hooksNode.PostToolUse)) {
            if ($h.matcher -eq "Edit|Write") {
                foreach ($c in @($h.hooks)) {
                    if ($c.command -like "*harness/edit-check.sh*") { $already = $true }
                }
            }
        }

        if (-not $already) {
            # $CLAUDE_PROJECT_DIR, not a cwd-relative path: a relative
            # "harness/..." only resolves when Claude Code happens to run
            # the hook from the project root.
            $entry = [PSCustomObject]@{
                matcher = "Edit|Write"
                hooks   = @([PSCustomObject]@{ type = "command"; command = 'bash "$CLAUDE_PROJECT_DIR"/harness/edit-check.sh'; timeout = 30 })
            }
            $hooksNode.PostToolUse = @($hooksNode.PostToolUse) + $entry
            Set-Utf8NoBom -Path $settingsPath -Content ($data | ConvertTo-Json -Depth 10)
            Say "  added PostToolUse hook to .claude/settings.json"
        } else {
            Say "  .claude/settings.json already has the harness edit-check hook"
        }
        }
    } else {
        Say "  (dry run) merge the PostToolUse hook into .claude/settings.json"
    }

    if (-not (Test-Path "$Target/.github/workflows/gates.yml")) {
        Invoke-Step "write .github/workflows/gates.yml" {
            New-Item -ItemType Directory -Force -Path "$Target/.github/workflows" | Out-Null
            Copy-Item "$kitRoot/templates/ci/gates.yml" "$Target/.github/workflows/gates.yml"
        }
    } else {
        Say "  .github/workflows/gates.yml already exists, leaving it alone."
    }

    Say ""
    Say "Done. If this is a fresh clone elsewhere, run:"
    Say "  git config core.hooksPath .githooks"
    Say "Edit harness/harness.config to wire in this project's format, lint, typecheck, and test commands."
    Say "Nothing was committed."
} finally {
    Pop-Location
}
