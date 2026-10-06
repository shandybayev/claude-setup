# Claude Code statusLine command, native PowerShell version. Use this instead
# of context-bar.sh only when Git Bash is not available; otherwise the .sh
# version is the one global/settings.json points at by default (see
# docs/INSTALL.md for how to switch). Needs PowerShell 5.1+ and git.
#
# Reads the hook JSON from stdin, same payload context-bar.sh reads.

$ESC = [char]27
$RESET = "$ESC[0m"
$GRAY = "$ESC[38;5;245m"
$BAR_EMPTY = "$ESC[38;5;238m"   # matches context-bar.sh's C_BAR_EMPTY
$ACCENT = "$ESC[38;5;66m"   # teal, matches context-bar.sh's default COLOR

# The block characters this script draws (U+2588/2584/2591) are outside the
# default Windows console codepage; without this they print as "?" under
# PowerShell 5.1's default output encoding.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$inputJson = [Console]::In.ReadToEnd()
$data = $inputJson | ConvertFrom-Json

$model = $data.model.display_name
if (-not $model) { $model = $data.model.id }
if (-not $model) { $model = "?" }

$cwd = $data.cwd
$dir = "?"
if ($cwd) { $dir = Split-Path -Leaf $cwd }

$branch = ""
$gitStatus = ""
if ($cwd -and (Test-Path $cwd)) {
    Push-Location $cwd
    try {
        $branch = (git branch --show-current 2>$null)
        if ($branch) {
            $fileCount = (git --no-optional-locks status --porcelain -uall 2>$null | Measure-Object -Line).Lines
            $upstream = (git rev-parse --abbrev-ref '@{upstream}' 2>$null)
            $syncStatus = "no upstream"
            if ($upstream) {
                $counts = (git rev-list --left-right --count 'HEAD...@{upstream}' 2>$null) -split "`t"
                $ahead = [int]$counts[0]
                $behind = [int]$counts[1]
                if ($ahead -eq 0 -and $behind -eq 0) { $syncStatus = "synced" }
                elseif ($ahead -gt 0 -and $behind -eq 0) { $syncStatus = "$ahead ahead" }
                elseif ($ahead -eq 0 -and $behind -gt 0) { $syncStatus = "$behind behind" }
                else { $syncStatus = "$ahead ahead, $behind behind" }
            }
            $gitStatus = "($fileCount files uncommitted, $syncStatus)"
        }
    } finally {
        Pop-Location
    }
}

$maxContext = $data.context_window.context_window_size
if (-not $maxContext) { $maxContext = 200000 }
$maxK = [int]($maxContext / 1000)
if ($maxK -ge 1000) { $maxDisplay = "$([int]($maxK / 1000))M" } else { $maxDisplay = "${maxK}k" }

$baseline = 20000
$barWidth = 10
$pctPrefix = ""
$pct = [int]($baseline * 100 / $maxContext)
$pctPrefix = "~"

$transcriptPath = $data.transcript_path
if ($transcriptPath -and (Test-Path $transcriptPath)) {
    try {
        $lastUsage = Get-Content $transcriptPath | ForEach-Object { $_ | ConvertFrom-Json -ErrorAction SilentlyContinue } |
            Where-Object { $_.message.usage -and $_.isSidechain -ne $true -and $_.isApiErrorMessage -ne $true } |
            Select-Object -Last 1
        if ($lastUsage) {
            $u = $lastUsage.message.usage
            $contextLength = [int]($u.input_tokens + $u.cache_read_input_tokens + $u.cache_creation_input_tokens)
            if ($contextLength -gt 0) {
                $pct = [int]($contextLength * 100 / $maxContext)
                $pctPrefix = ""
            }
        }
    } catch {
        # Fall back to the baseline estimate already set above.
    }
}
if ($pct -gt 100) { $pct = 100 }

$bar = ""
for ($i = 0; $i -lt $barWidth; $i++) {
    $progress = $pct - ($i * 10)
    if ($progress -ge 8) { $bar += "$ACCENT$([char]0x2588)$RESET" }
    elseif ($progress -ge 3) { $bar += "$ACCENT$([char]0x2584)$RESET" }
    else { $bar += "$BAR_EMPTY$([char]0x2591)$RESET" }
}
$ctx = "$bar $GRAY$pctPrefix$pct% of $maxDisplay tokens"

$output = "$ACCENT$model$GRAY | $dir"
if ($branch) { $output += " | $branch $gitStatus" }
$output += " | $ctx$RESET"

Write-Host $output
