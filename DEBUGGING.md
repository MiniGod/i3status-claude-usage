# Debugging the `CC: err` issue

## Symptom

`claude-usage.sh` displayed `CC: err` consistently, all day, at a 60-second polling interval.

## Debugging Process

### 1. Read the script

The `CC: err` message comes from the `curl` error handler on lines 28-32. The `-f` flag makes curl return a non-zero exit code on HTTP errors, so the script falls through to the error handler without any detail.

### 2. Tested the API call with verbose output

Replaced `-sf` with `-v` to see the full HTTP exchange. This revealed:

- **HTTP 429** response (rate limited)
- `retry-after: 0` header (contradictory -- says retry immediately but keeps rejecting)
- Body: `{"error":{"message":"Rate limited. Please try again later.","type":"rate_limit_error"}}`

### 3. Ruled out obvious causes

- Checked the OAuth token wasn't expired -- `expiresAt` was later that day
- Confirmed the token, refresh token, and subscription type (`pro`) all looked valid
- The 60-second polling interval seemed reasonable, so true rate limiting was unlikely

### 4. Reverse-engineered Claude Code's own API call

Since Claude Code itself successfully shows usage data, I compared how it calls the same endpoint by grepping through the minified `cli.js` bundle:

```bash
grep -aoP '.{0,100}oauth/usage.{0,100}' .../claude-code/cli.js
```

This showed Claude Code sends three headers:

- `Authorization: Bearer <token>` (same as the script)
- `anthropic-beta: oauth-2025-04-20` (same as the script)
- **`User-Agent: claude-code/<version>`** (missing from the script)

The `User-Agent` value was constructed by function `zz()` which returns `claude-code/<VERSION>`. The beta header value was found by grepping for the variable `At=` referenced in the auth function `mF()`.

### 5. Confirmed the fix

Tested with `curl` adding just the `User-Agent` header -- got a 200 with valid JSON immediately. The 429 was never about rate limiting; it was the API rejecting requests without the expected `User-Agent`.

## Root cause

The `/api/oauth/usage` endpoint requires a `User-Agent: claude-code/<version>` header. Without it, it returns HTTP 429 -- misleadingly framed as rate limiting rather than a 403 or 400.

## Fixes applied

1. Added `User-Agent` header matching what Claude Code sends, auto-detecting the installed version
2. Added 60-second file-based caching to avoid unnecessary API calls
3. Improved error reporting -- now shows `CC: HTTP 429` instead of generic `CC: err`
