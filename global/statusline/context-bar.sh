#!/bin/bash
# Claude Code statusLine command. Prints: model | directory | git branch and
# uncommitted/sync state | a context-usage bar. Needs bash + git + jq.

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
COLOR="teal"

C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'
C_BAR_EMPTY='\033[38;5;238m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;
esac

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Git branch, uncommitted file count, and sync status against upstream.
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                sync_status="synced"
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        if [[ "$file_count" -eq 0 ]]; then
            git_status="(0 files uncommitted, ${sync_status})"
        else
            git_status="(${file_count} files uncommitted, ${sync_status})"
        fi
    fi
fi

# Context-usage bar, estimated from the transcript's running token usage.
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
# jq's own "// 200000" only covers a null/missing field; malformed or empty
# stdin makes jq fail outright, which leaves max_context as an empty string
# and every arithmetic use below as a division by zero. Re-check after jq.
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)
[[ "$max_context" =~ ^[0-9]+$ ]] && [ "$max_context" -gt 0 ] || max_context=200000
max_k=$((max_context / 1000))
if [[ $max_k -ge 1000 ]]; then
    max_display="$((max_k / 1000))M"
else
    max_display="${max_k}k"
fi

# A fresh session already carries roughly this many tokens of fixed overhead
# (system prompt, tool schemas, memory). Used as the estimate before the
# transcript has its first usage entry.
baseline=20000
bar_width=10
pct_prefix=""

if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_length=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript_path" 2>/dev/null)
    if [[ -n "$context_length" && "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
    else
        pct=$((baseline * 100 / max_context))
        pct_prefix="~"
    fi
else
    pct=$((baseline * 100 / max_context))
    pct_prefix="~"
fi
[[ $pct -gt 100 ]] && pct=100

bar=""
for ((i=0; i<bar_width; i++)); do
    progress=$((pct - i * 10))
    if [[ $progress -ge 8 ]]; then
        bar+="${C_ACCENT}█${C_RESET}"
    elif [[ $progress -ge 3 ]]; then
        bar+="${C_ACCENT}▄${C_RESET}"
    else
        bar+="${C_BAR_EMPTY}░${C_RESET}"
    fi
done
ctx="${bar} ${C_GRAY}${pct_prefix}${pct}% of ${max_display} tokens"

output="${C_ACCENT}${model}${C_GRAY} | ${dir}"
[[ -n "$branch" ]] && output+=" | ${branch} ${git_status}"
output+=" | ${ctx}${C_RESET}"

printf '%b\n' "$output"
