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
LOG_FILE="${CLAUDE_USAGE_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

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

FIVE_H_RAW=$(echo "$RESPONSE" | jq -r '.five_hour.utilization // 0')
FIVE_H=$(echo "$RESPONSE" | jq -r '(.five_hour.utilization // 0) | round')
FIVE_H_RESET=$(echo "$RESPONSE" | jq -r '.five_hour.resets_at // empty')
SEVEN_D=$(echo "$RESPONSE" | jq -r '(.seven_day.utilization // 0) | round')
SEVEN_D_RESET=$(echo "$RESPONSE" | jq -r '.seven_day.resets_at // empty')

FIVE_H_LEFT=$(time_left "$FIVE_H_RESET")
SEVEN_D_LEFT=$(time_left "$SEVEN_D_RESET")

now_epoch=$(date +%s)
reset_epoch=""
left_sec=0
if [[ -n "$FIVE_H_RESET" ]]; then
    reset_epoch=$(date -d "$FIVE_H_RESET" +%s 2>/dev/null || echo "")
fi
if [[ -n "$reset_epoch" ]]; then
    left_sec=$((reset_epoch - now_epoch))
fi

# Project end-of-window usage: used × window / elapsed (5h = 18000s).
FIVE_H_PROJ=""
if [[ -n "$reset_epoch" ]]; then
    elapsed_sec=$((18000 - left_sec))
    if ((elapsed_sec >= 60 && left_sec > 0 && left_sec <= 18000)); then
        FIVE_H_PROJ=$(( (FIVE_H * 18000 + elapsed_sec / 2) / elapsed_sec ))
    fi
fi

# Recent burn rate + extrapolation from it: find usage at ~10 min ago in this
# session window (linear interp between straddling log entries, else closest),
# show the delta and extend the rate to end-of-window.
RECENT_STR=""
if [[ -n "$reset_epoch" && -f "$LOG_FILE" && $left_sec -gt 0 ]]; then
    target=$((now_epoch - 600))
    result=$(awk \
        -v target="$target" -v reset="$reset_epoch" -v now="$now_epoch" \
        -v cur="$FIVE_H_RAW" -v left="$left_sec" '
        ($3 + 0) == reset && ($1 + 0) <= now {
            t[++n] = $1 + 0
            u[n] = $2 + 0
        }
        END {
            if (n == 0) exit
            lo = 0; hi = 0
            for (i = 1; i <= n; i++) {
                if (t[i] <= target) lo = i
                else { hi = i; break }
            }
            if (lo && hi) {
                frac = (target - t[lo]) / (t[hi] - t[lo])
                past_u = u[lo] + frac * (u[hi] - u[lo])
                past_t = target
            } else if (lo) {
                past_u = u[lo]; past_t = t[lo]
            } else {
                past_u = u[1]; past_t = t[1]
            }
            age = now - past_t
            if (age < 60) exit
            d = cur - past_u
            di = (d >= 0) ? int(d + 0.5) : -int(-d + 0.5)
            proj = cur + (d / age) * left
            if (proj < 0) proj = 0
            mins = int((age + 30) / 60)
            label = (past_t == target) ? "10m" : (mins "m")
            sign = (di < 0) ? "" : "+"
            printf "%s%d %s %d\n", sign, di, label, int(proj + 0.5)
        }
    ' "$LOG_FILE")
    if [[ -n "$result" ]]; then
        read -r delta_str label recent_proj <<< "$result"
        RECENT_STR=" ${delta_str}%/${label}→${recent_proj}%"
    fi
fi

# Append current reading; prune entries older than 6h.
if [[ -n "$reset_epoch" ]]; then
    {
        [[ -f "$LOG_FILE" ]] && awk -v cutoff=$((now_epoch - 21600)) '($1 + 0) >= cutoff' "$LOG_FILE" 2>/dev/null
        printf '%d\t%s\t%d\n' "$now_epoch" "$FIVE_H_RAW" "$reset_epoch"
    } > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

if [[ -n "$FIVE_H_PROJ" ]]; then
    FIVE_H_STR="${FIVE_H}%→${FIVE_H_PROJ}%"
else
    FIVE_H_STR="${FIVE_H}%"
fi

echo "CC: ${FIVE_H_STR}${RECENT_STR} 5h (${FIVE_H_LEFT}) | ${SEVEN_D}% 7d (${SEVEN_D_LEFT})"
