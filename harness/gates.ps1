# PowerShell wrapper for harness/gates.sh. Same arguments, same exit code.
# Exists because a pre-commit/pre-push hook on Windows may be invoked through
# either shell; this just forwards to bash so there is still only ONE gate
# script to maintain. Needs Git Bash (or any bash) on PATH.
#
# Usage: gates.ps1 <commit|push|all|commit-msg> [commit-msg-file]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Mode,

    [Parameter(Position = 1)]
    [string]$CommitMsgFile
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Git for Windows first, deliberately ahead of a plain PATH lookup: Windows
# ships its own system32\bash.exe that only forwards to WSL, and on a
# machine with WSL absent or unconfigured that stub is still first on PATH,
# fails at execve time, and masquerades as "no bash" with a confusing error.
$bash = $null
foreach ($candidate in @("C:\Program Files\Git\bin\bash.exe", "C:\Program Files\Git\usr\bin\bash.exe")) {
    if (Test-Path $candidate) { $bash = $candidate; break }
}
if (-not $bash) {
    $bash = (Get-Command bash.exe -ErrorAction SilentlyContinue).Source
}
if (-not $bash) {
    Write-Error "harness: no bash found. Install Git for Windows (ships Git Bash)."
    exit 1
}

$scriptPath = Join-Path $here "gates.sh"
if ($CommitMsgFile) {
    & $bash $scriptPath $Mode $CommitMsgFile
} else {
    & $bash $scriptPath $Mode
}
exit $LASTEXITCODE
