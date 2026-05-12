#!/usr/bin/env bash
# Claude Code usage for i3status/i3xrocks
# Shows 5h window and 7-day utilization percentages

set -euo pipefail

# Open usage page on click (BUTTON is set by i3blocks/i3xrocks)
if [[ "${button:-}" == "1" ]]; then
    xdg-open "https://claude.ai/settings/usage" &>/dev/null &
fi

CLAUDE_VERSION="${CLAUDE_VERSION:-$(claude --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "2.1.69")}"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CREDENTIALS_FILE="$CLAUDE_CONFIG_DIR/.credentials.json"
API_URL="https://api.anthropic.com/api/oauth/usage"

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    echo "CC: no creds"
    exit 0
fi

TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDENTIALS_FILE")

if [[ -z "$TOKEN" ]]; then
    echo "CC: no token"
    exit 0
fi

RESPONSE=$(curl -s --max-time 5 -w '\n%{http_code}' "$API_URL" \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/${CLAUDE_VERSION:-2.1.69}") || {
    echo "CC: err"
    exit 0
}

HTTP_CODE=$(tail -1 <<< "$RESPONSE")
RESPONSE=$(sed '$d' <<< "$RESPONSE")

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "CC: HTTP $HTTP_CODE"
    exit 0
fi

time_left() {
    local reset="$1"
    local reset_epoch now_epoch diff h m d
    reset_epoch=$(date -d "$reset" +%s 2>/dev/null) || { echo "?"; return; }
    now_epoch=$(date +%s)
    diff=$((reset_epoch - now_epoch))
    if ((diff <= 0)); then echo "0m"; return; fi
    d=$((diff / 86400))
    h=$(( (diff % 86400) / 3600 ))
    m=$(( (diff % 3600) / 60 ))
    if ((d > 0)); then echo "${d}d${h}h"
    elif ((h > 0)); then echo "${h}h${m}m"
    else echo "${m}m"
    fi
}

FIVE_H=$(echo "$RESPONSE" | jq -r '(.five_hour.utilization // 0) | round')
FIVE_H_RESET=$(echo "$RESPONSE" | jq -r '.five_hour.resets_at // empty')
SEVEN_D=$(echo "$RESPONSE" | jq -r '(.seven_day.utilization // 0) | round')
SEVEN_D_RESET=$(echo "$RESPONSE" | jq -r '.seven_day.resets_at // empty')

FIVE_H_LEFT=$(time_left "$FIVE_H_RESET")
SEVEN_D_LEFT=$(time_left "$SEVEN_D_RESET")

# Project end-of-window usage: used × window / elapsed.
# Window is 5h (18000s); elapsed = 18000 - time_left_sec.
FIVE_H_PROJ=""
if [[ -n "$FIVE_H_RESET" ]]; then
    reset_epoch=$(date -d "$FIVE_H_RESET" +%s 2>/dev/null || echo "")
    if [[ -n "$reset_epoch" ]]; then
        now_epoch=$(date +%s)
        left_sec=$((reset_epoch - now_epoch))
        elapsed_sec=$((18000 - left_sec))
        # Need at least 60s elapsed and a valid window to extrapolate.
        if ((elapsed_sec >= 60 && left_sec > 0 && left_sec <= 18000)); then
            FIVE_H_PROJ=$(( (FIVE_H * 18000 + elapsed_sec / 2) / elapsed_sec ))
        fi
    fi
fi

if [[ -n "$FIVE_H_PROJ" ]]; then
    FIVE_H_STR="${FIVE_H}%→${FIVE_H_PROJ}%"
else
    FIVE_H_STR="${FIVE_H}%"
fi

echo "CC: ${FIVE_H_STR} 5h (${FIVE_H_LEFT}) | ${SEVEN_D}% 7d (${SEVEN_D_LEFT})"
