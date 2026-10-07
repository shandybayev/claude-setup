# Profile loading, validation, and agent-frontmatter rendering, shared by
# install.ps1 and uninstall.ps1. Dot-source this file; it defines functions
# only, no side effects.
#
# A profile picks model and effort per role (plus the main session's model
# and effort, the workflow mode, and the parallel-teammate cap) for one
# usage weight: see profiles/*.json. The shape is fixed and every key is
# required (see $script:ProfileRequired* below); an unknown or missing key
# fails validation with a message naming it, rather than being silently
# ignored.
#
# profile.sh is the same contract for Bash, implemented separately (no
# shared interpreter can be assumed across both platforms); the two must
# agree on what counts as valid and on where "agents" links for each
# profile, but do not share code.

$script:ProfileRequiredTop = @("name", "description", "main", "workflowMode", "maxParallelTeammates", "roles")
# Allowed but not required: a profile that omits one falls back to this
# kit's own default (see each key's own reader -- session_context.py's
# resolve_context_cap, for sessionContextChars). Keeping these OUT of
# ProfileRequiredTop is what lets an older or hand-written profile
# file, missing a key added later, still validate.
$script:ProfileOptionalTop = @("sessionContextChars")
$script:ProfileRequiredMain = @("model", "effortLevel")
$script:ProfileRequiredRoleFields = @("model", "effort")
$script:ProfileRequiredRoles = @(
    "planner", "plan-reviewer", "builder", "adversarial-reviewer",
    "probe", "plan-reviewer-critical", "builder-critical"
)
$script:ProfileValidWorkflowModes = @("full", "lean", "solo")

# Get-ProfileValidNames <profilesDir> -- every profile this install knows
# about, derived from the files actually present rather than a second,
# separately-maintained list that could drift from them.
function Get-ProfileValidNames($profilesDir) {
    if (-not (Test-Path $profilesDir)) { return @() }
    Get-ChildItem -File -Path $profilesDir -Filter "*.json" |
        ForEach-Object { $_.BaseName } |
        Sort-Object
}

# Test-ProfileValid <path> -- parses and validates one profile file against
# the fixed shape. Returns {Valid, Error, Profile}: Profile is the parsed
# object only when Valid is true. Never throws; a parse failure is reported
# through Error like any other validation failure, so a caller never needs
# a separate try/catch around this.
function Test-ProfileValid($path) {
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{ Valid = $false; Error = "profile file not found: $path"; Profile = $null }
    }
    try {
        $raw = Get-Content -Path $path -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{ Valid = $false; Error = "malformed profile JSON in ${path}: $($_.Exception.Message)"; Profile = $null }
    }
    if ($null -eq $obj -or $obj -isnot [System.Management.Automation.PSCustomObject]) {
        return [PSCustomObject]@{ Valid = $false; Error = "malformed profile JSON in ${path}: top level is not a JSON object"; Profile = $null }
    }

    $fail = { param($msg) [PSCustomObject]@{ Valid = $false; Error = $msg; Profile = $null } }

    $topKeys = @($obj.PSObject.Properties.Name)
    $missingTop = @($script:ProfileRequiredTop | Where-Object { $_ -notin $topKeys })
    if ($missingTop.Count -gt 0) { return & $fail "missing top-level key(s): $($missingTop -join ', ')" }
    $allowedTop = @($script:ProfileRequiredTop + $script:ProfileOptionalTop)
    $extraTop = @($topKeys | Where-Object { $_ -notin $allowedTop })
    if ($extraTop.Count -gt 0) { return & $fail "unknown top-level key(s): $($extraTop -join ', ')" }

    if ($script:ProfileValidWorkflowModes -notcontains $obj.workflowMode) {
        return & $fail "workflowMode must be one of: $($script:ProfileValidWorkflowModes -join ', ') (got '$($obj.workflowMode)')"
    }

    if ($topKeys -contains "sessionContextChars") {
        $capVal = $obj.sessionContextChars
        if (-not ($capVal -is [int] -or $capVal -is [long]) -or $capVal -le 0) {
            return & $fail "sessionContextChars must be a positive integer (got '$capVal')"
        }
    }

    if ($obj.main -isnot [System.Management.Automation.PSCustomObject]) {
        return & $fail "'main' must be an object"
    }
    $mainKeys = @($obj.main.PSObject.Properties.Name)
    $missingMain = @($script:ProfileRequiredMain | Where-Object { $_ -notin $mainKeys })
    if ($missingMain.Count -gt 0) { return & $fail "missing main key(s): $($missingMain -join ', ')" }
    $extraMain = @($mainKeys | Where-Object { $_ -notin $script:ProfileRequiredMain })
    if ($extraMain.Count -gt 0) { return & $fail "unknown main key(s): $($extraMain -join ', ')" }

    if ($obj.roles -isnot [System.Management.Automation.PSCustomObject]) {
        return & $fail "'roles' must be an object"
    }
    $roleKeys = @($obj.roles.PSObject.Properties.Name)
    $missingRoles = @($script:ProfileRequiredRoles | Where-Object { $_ -notin $roleKeys })
    if ($missingRoles.Count -gt 0) { return & $fail "missing role(s): $($missingRoles -join ', ')" }
    $extraRoles = @($roleKeys | Where-Object { $_ -notin $script:ProfileRequiredRoles })
    if ($extraRoles.Count -gt 0) { return & $fail "unknown role(s): $($extraRoles -join ', ')" }

    foreach ($r in $script:ProfileRequiredRoles) {
        $roleObj = $obj.roles.$r
        if ($roleObj -isnot [System.Management.Automation.PSCustomObject]) {
            return & $fail "role '$r' must be an object"
        }
        $roleFieldKeys = @($roleObj.PSObject.Properties.Name)
        $missingRoleFields = @($script:ProfileRequiredRoleFields | Where-Object { $_ -notin $roleFieldKeys })
        if ($missingRoleFields.Count -gt 0) { return & $fail "role '$r' missing key(s): $($missingRoleFields -join ', ')" }
        $extraRoleFields = @($roleFieldKeys | Where-Object { $_ -notin $script:ProfileRequiredRoleFields })
        if ($extraRoleFields.Count -gt 0) { return & $fail "role '$r' has unknown key(s): $($extraRoleFields -join ', ')" }
    }

    return [PSCustomObject]@{ Valid = $true; Error = $null; Profile = $obj }
}

# Render-ProfileAgents <profileObj> <srcDir> <destDir> [-DryRun]
# Renders every agent file from $srcDir into $destDir: the 7 role files
# get only their `model:` and `effort:` frontmatter lines replaced (the
# span between the first two lines that are exactly "---"), everything
# else -- including line endings -- passing through unchanged (files are
# read and written as raw text, never Get-Content/Set-Content, which can
# normalize line endings or add a BOM); any OTHER `*.md` file in $srcDir
# (not one of the 7 roles) is copied through byte for byte, so a file
# added to agents/ later is present for every profile, not just max.
#
# Built in a sibling temp folder first and swapped into $destDir only on
# complete success: a failure partway through (a missing file, a bad
# frontmatter shape) throws, cleans up the temp folder, and never touches
# $destDir at all -- a previous render there, from an earlier run,
# survives untouched, instead of being left half-overwritten.
#
# Returns one change record per role (Role, File, OldModel, NewModel,
# OldEffort, NewEffort) whether or not -DryRun is set, so a dry run can
# print exactly what would change. With -DryRun, nothing is written or
# swapped at all.
function Render-ProfileAgents($profileObj, $srcDir, $destDir, [switch]$DryRun) {
    $changes = @()
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $tmpDir = $null
    if (-not $DryRun) {
        $tmpDir = "$destDir.tmp-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    }
    try {
        foreach ($role in $script:ProfileRequiredRoles) {
            $srcFile = Join-Path $srcDir "$role.md"
            if (-not (Test-Path $srcFile)) { throw "agent file not found: $srcFile" }
            $content = [System.IO.File]::ReadAllText($srcFile)
            $lines = $content -split "`n"
            if ($lines.Length -lt 2 -or $lines[0].TrimEnd("`r") -ne '---') {
                throw "agent file $srcFile does not start with a frontmatter delimiter (---)"
            }
            $endIdx = -1
            for ($i = 1; $i -lt $lines.Length; $i++) {
                if ($lines[$i].TrimEnd("`r") -eq '---') { $endIdx = $i; break }
            }
            if ($endIdx -lt 0) { throw "agent file $srcFile never closes its frontmatter (---)" }

            $roleCfg = $profileObj.roles.$role
            $newModel = $roleCfg.model
            $newEffort = $roleCfg.effort
            $oldModel = $null
            $oldEffort = $null
            for ($i = 1; $i -lt $endIdx; $i++) {
                if ($lines[$i] -match '^model:\s*(.*?)\r?$') {
                    $oldModel = $Matches[1]
                    $lines[$i] = "model: $newModel"
                } elseif ($lines[$i] -match '^effort:\s*(.*?)\r?$') {
                    $oldEffort = $Matches[1]
                    $lines[$i] = "effort: $newEffort"
                }
            }
            if ($null -eq $oldModel -or $null -eq $oldEffort) {
                throw "agent file $srcFile is missing a model: or effort: line in its frontmatter"
            }

            $changes += [PSCustomObject]@{
                Role = $role; File = "$role.md"
                OldModel = $oldModel; NewModel = $newModel
                OldEffort = $oldEffort; NewEffort = $newEffort
            }

            if (-not $DryRun) {
                $newContent = [string]::Join("`n", $lines)
                $destFile = Join-Path $tmpDir "$role.md"
                [System.IO.File]::WriteAllText($destFile, $newContent, $utf8NoBom)
            }
        }

        if (-not $DryRun) {
            Get-ChildItem -File -Path $srcDir -Filter "*.md" | ForEach-Object {
                if ($script:ProfileRequiredRoles -notcontains $_.BaseName) {
                    Copy-Item $_.FullName (Join-Path $tmpDir $_.Name) -Force
                }
            }
        }
    } catch {
        if ($tmpDir -and (Test-Path $tmpDir)) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }

    if (-not $DryRun) {
        if (Test-Path $destDir) { Remove-Item $destDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destDir) | Out-Null
        Move-Item -Path $tmpDir -Destination $destDir -Force
    }
    return $changes
}

# Render-ProfileSettings <profileObj> <srcSettings> <destSettings> [-DryRun]
# Renders srcSettings (global/settings.json) into destSettings for a
# non-max profile: replaces ONLY the top-level "model" and "effortLevel"
# values and the "modelSettings" block's two per-model effortLevel
# values (both set to this profile's own main.effortLevel, so manually
# switching models mid-session under this profile does not jump to a
# different effort than the profile already chose). Every other key,
# line, and line ending is kept exactly as in srcSettings -- a targeted
# text substitution on this repo's own fixed, known layout, the same
# technique Render-ProfileAgents uses on the agent files, not a real
# JSON round-trip (ConvertTo-Json) that could reformat or reorder
# anything.
#
# Written to a sibling temp file first and renamed into place, so a
# failure never leaves destSettings partial. With -DryRun, nothing is
# written; this only validates that srcSettings has the expected shape.
function Render-ProfileSettings($profileObj, $srcSettings, $destSettings, [switch]$DryRun) {
    $model = $profileObj.main.model
    $effort = $profileObj.main.effortLevel
    $content = [System.IO.File]::ReadAllText($srcSettings)
    $lines = $content -split "`n"
    if ($lines.Length -lt 1 -or $lines[0].TrimEnd("`r") -ne '{') {
        throw "$srcSettings does not start with a bare {"
    }
    if (-not ($lines | Where-Object { $_ -match '^  "model":' }) -or
        -not ($lines | Where-Object { $_ -match '^  "effortLevel":' })) {
        throw "$srcSettings is missing a top-level model/effortLevel key in the expected shape"
    }
    $msIdx = -1
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i].TrimEnd("`r") -eq '  "modelSettings": {') { $msIdx = $i; break }
    }
    if ($msIdx -lt 0) {
        throw "$srcSettings is missing a modelSettings block in the expected shape"
    }
    $msEnd = -1
    for ($i = $msIdx + 1; $i -lt $lines.Length; $i++) {
        if ($lines[$i].TrimEnd("`r") -eq '  },') { $msEnd = $i; break }
    }
    if ($msEnd -lt 0) {
        throw "$srcSettings never closes its modelSettings block in the expected shape"
    }

    if ($DryRun) { return }

    # Walks each "<model-id>": { "effortLevel": "..." } entry inside
    # modelSettings individually, so an entry for a model THIS profile
    # does not mention (added by hand, or a model this repo adds later)
    # passes through completely untouched -- only the two model ids this
    # profile actually sets (claude-opus-5-5, claude-sonnet-5) get their
    # effortLevel value replaced; nothing is ever added or removed, and
    # no entry is rebuilt from scratch.
    $knownModels = @("claude-opus-5-5", "claude-sonnet-5")
    $curModel = $null
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $trimmed = $line.TrimEnd("`r")
        if ($i -gt $msIdx -and $i -lt $msEnd) {
            if ($trimmed -match '^    "([^"]+)": \{$') {
                $curModel = $Matches[1]
                $out.Add($line)
                continue
            }
            if ($trimmed -match '^      "effortLevel":' -and $knownModels -contains $curModel) {
                $out.Add(($trimmed -replace '"[^"]*"\s*$', "`"$effort`""))
                continue
            }
            $out.Add($line)
            continue
        }
        if ($trimmed -match '^  "model":') {
            $out.Add("  ""model"": ""$model"",")
        } elseif ($trimmed -match '^  "effortLevel":') {
            $out.Add("  ""effortLevel"": ""$effort"",")
        } else {
            $out.Add($line)
        }
    }
    $newContent = [string]::Join("`n", $out)
    $tmp = "$destSettings.tmp-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tmp) | Out-Null
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $newContent, $utf8NoBom)
    if (Test-Path $destSettings) { Remove-Item $destSettings -Force }
    Move-Item -Path $tmp -Destination $destSettings -Force
}

# Test-MaxProfileConsistency <maxProfileObj> <agentsDir> <settingsJson> --
# For the max profile specifically: max.json carries values that are
# NEVER rendered anywhere (max links agents/ and settings.json straight
# from the repo, unchanged), so nothing else enforces that it still
# matches the agent files' own frontmatter or settings.json's own
# top-level model/effortLevel. Returns {Valid, Error}: Error names which
# role or field drifted, rather than silently installing from the
# (correct) agent files and settings.json while printing a "model X ->
# Y" change from max.json that is never actually applied.
function Test-MaxProfileConsistency($profileObj, $agentsDir, $settingsPath) {
    foreach ($role in $script:ProfileRequiredRoles) {
        $roleCfg = $profileObj.roles.$role
        $agentFile = Join-Path $agentsDir "$role.md"
        $content = [System.IO.File]::ReadAllText($agentFile)
        $lines = $content -split "`n"
        $oldModel = $null
        $oldEffort = $null
        for ($i = 1; $i -lt $lines.Length; $i++) {
            if ($lines[$i].TrimEnd("`r") -eq '---') { break }
            if ($lines[$i] -match '^model:\s*(.*?)\r?$') { $oldModel = $Matches[1] }
            elseif ($lines[$i] -match '^effort:\s*(.*?)\r?$') { $oldEffort = $Matches[1] }
        }
        if ($roleCfg.model -ne $oldModel -or $roleCfg.effort -ne $oldEffort) {
            return [PSCustomObject]@{
                Valid = $false
                Error = "profiles/max.json role '$role' (model=$($roleCfg.model) effort=$($roleCfg.effort)) does not match $agentFile (model=$oldModel effort=$oldEffort). To change max, edit the agent files AND max.json together."
            }
        }
    }
    $settingsObj = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    if ($profileObj.main.model -ne $settingsObj.model -or $profileObj.main.effortLevel -ne $settingsObj.effortLevel) {
        return [PSCustomObject]@{
            Valid = $false
            Error = "profiles/max.json main (model=$($profileObj.main.model) effortLevel=$($profileObj.main.effortLevel)) does not match $settingsPath (model=$($settingsObj.model) effortLevel=$($settingsObj.effortLevel)). To change max, edit settings.json AND max.json together."
        }
    }
    return [PSCustomObject]@{ Valid = $true; Error = $null }
}

# Get-ProfileAgentsSource <here> <target> -- the directory "agents" should
# link to for whichever profile is recorded at <target>/claude-setup-profile.json
# (max: the repo's own agents/; anything else: that profile's OWN rendered
# .profile-build/<name>/agents, never shared with any other profile's
# target). Falls back to "max" when there is no record yet, or it cannot
# be read, since that is this installer's own default profile.
function Get-ProfileAgentsSource($here, $target) {
    $recordPath = Join-Path $target "claude-setup-profile.json"
    $name = "max"
    if (Test-Path $recordPath) {
        try {
            $rec = Get-Content -Path $recordPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($rec.name) { $name = $rec.name }
        } catch {}
    }
    if ($name -eq "max") {
        return (Join-Path $here "agents")
    }
    return (Join-Path $here ".profile-build/$name/agents")
}

# Get-ProfileSettingsSource <here> <target> -- the same resolution as
# Get-ProfileAgentsSource, for "settings.json": max: global/settings.json
# itself; anything else: that profile's own rendered
# .profile-build/<name>/settings.json. settings.json is installed as a
# plain copy for every non-max profile (see install.ps1's
# Install-ProfileSettings), so this mostly matters if settings.json is
# somehow still a link at that path (a manual edit, or a manifest line
# that was never refreshed); uninstall needs the right source either way
# to tell whether a link still resolves into this repo before removing it.
function Get-ProfileSettingsSource($here, $target) {
    $recordPath = Join-Path $target "claude-setup-profile.json"
    $name = "max"
    if (Test-Path $recordPath) {
        try {
            $rec = Get-Content -Path $recordPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($rec.name) { $name = $rec.name }
        } catch {}
    }
    if ($name -eq "max") {
        return (Join-Path $here "global/settings.json")
    }
    return (Join-Path $here ".profile-build/$name/settings.json")
}

# The menu's display order is fixed (max first, as the most familiar
# choice, then standard, then lite), NOT the alphabetical order
# Get-ProfileValidNames returns. Filtered to whatever profiles actually
# exist, so a missing file just drops out of the menu instead of crashing
# it; any OTHER profile this repo ever grows is appended after these three
# in whatever order Get-ProfileValidNames gives it, so the menu never
# silently omits a real profile.
function Get-ProfileMenuOrder($validNames) {
    $preferred = @("max", "standard", "lite")
    $ordered = @($preferred | Where-Object { $_ -in $validNames })
    $ordered += @($validNames | Where-Object { $_ -notin $preferred })
    return $ordered
}

# Read-ProfileChoice <profilesDir> <menuOrder> -- prints the menu (each
# profile's own `description` field, never duplicated by hand) and reads
# one line of input, retrying up to 3 times. Accepts a 1-based index into
# menuOrder, a profile name (case-insensitive), or an empty line for the
# default (menuOrder's first entry). Returns the chosen name, or $null
# after 3 invalid attempts -- the caller exits non-zero on $null, touching
# nothing.
function Read-ProfileChoice($profilesDir, $menuOrder) {
    Write-Host "Which Claude plan do you have? This sets the models, effort, and how many teammates run at once."
    Write-Host ""
    for ($i = 0; $i -lt $menuOrder.Count; $i++) {
        $name = $menuOrder[$i]
        $check = Test-ProfileValid (Join-Path $profilesDir "$name.json")
        $desc = if ($check.Valid) { $check.Profile.description } else { "(description unavailable)" }
        Write-Host ("  {0}) {1,-10} {2}" -f ($i + 1), $name, $desc)
    }
    Write-Host ""
    Write-Host "Not sure? Pick the cheaper one; you can switch later with: install.ps1 -Update -Profile <name>"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $raw = Read-Host -Prompt "Choice [1-$($menuOrder.Count), default 1]"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $menuOrder[0] }
        $trimmed = $raw.Trim()
        if ($trimmed -match '^\d+$') {
            $idx = [int]$trimmed
            if ($idx -ge 1 -and $idx -le $menuOrder.Count) { return $menuOrder[$idx - 1] }
        } else {
            $match = @($menuOrder | Where-Object { $_ -ieq $trimmed })
            if ($match.Count -gt 0) { return $match[0] }
        }
        Write-Host "Not a valid choice. Enter 1-$($menuOrder.Count) or a profile name."
    }
    return $null
}

# ConvertTo-UnixPath <winPath> -- best-effort Unix-style conversion of a
# Windows-style absolute path (C:\Users\... -> /c/Users/...), used only
# to make the Mac/Linux example command in Write-ProfileRequiredMessage
# look like something you would actually type there; a path that is
# not drive-letter-shaped passes through unchanged.
function ConvertTo-UnixPath($path) {
    if ($path -match '^([A-Za-z]):(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        return "/$drive$rest"
    }
    return $path
}

# Write-ProfileRequiredMessage <profilesDir> <menuOrder> <yesGiven>
# [targetArg] -- printed when a profile cannot be chosen without asking
# (a first-time install, no -Profile, running non-interactively or with
# -Yes): there is no safe default to fall back on, so this names the
# three profiles with their own description (never duplicated by hand,
# same as Read-ProfileChoice), the exact command for each shell
# (carrying over $targetArg, if one was given, converted to THAT
# shell's own path style -- as-is for the PowerShell example, since
# $targetArg arrives in PowerShell's own Windows style, and
# ConvertTo-UnixPath for the Mac/Linux one -- and $yesGiven
# distinguishing a real non-interactive run from -Yes in a real
# console, so the message never claims the wrong one), and a line
# addressed to an AI assistant running the installer on someone else's
# behalf.
function Write-ProfileRequiredMessage($profilesDir, $menuOrder, [bool]$yesGiven, [string]$targetArg) {
    if ($yesGiven) {
        Write-Host "A profile is required: -Yes was given, but no profile is recorded yet and there is no safe default to fall back on."
    } else {
        Write-Host "A profile is required: this is a first-time install (no profile recorded yet) running non-interactively, so there is no safe default to fall back on."
    }
    Write-Host ""
    $psTarget = if ($targetArg) { " -Target `"$targetArg`"" } else { "" }
    $shTarget = if ($targetArg) { " --target `"$(ConvertTo-UnixPath $targetArg)`"" } else { "" }
    foreach ($name in $menuOrder) {
        $check = Test-ProfileValid (Join-Path $profilesDir "$name.json")
        $desc = if ($check.Valid) { $check.Profile.description } else { "(description unavailable)" }
        Write-Host ("  {0,-10} {1}" -f $name, $desc)
        Write-Host "    PowerShell: powershell -ExecutionPolicy Bypass -File install.ps1 -Profile $name$psTarget"
        Write-Host "    Mac/Linux:  ./install.sh --profile $name$shTarget"
    }
    Write-Host ""
    Write-Host "If you are an AI assistant running this for someone, ask them which plan they have and re-run with -Profile <name>."
}
