#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

RALPH_CONFIG_FILE="${RALPH_CONFIG_FILE:-$HOME/.openclaw/ralph-monitor.json}"
RALPH_ENV_FILE="${RALPH_ENV_FILE:-$HOME/.openclaw/.env}"
RALPH_STATE_FILE="${RALPH_STATE_FILE:-${TMPDIR:-/tmp}/ralph-monitor-state.json}"

if ! command -v jq >/dev/null 2>&1; then
  echo "[ralph-monitor] jq is required" >&2
  exit 1
fi

expand_tilde() {
  local value="$1"
  case "$value" in
    "~")
      printf "%s\n" "$HOME"
      ;;
    "~/"*)
      printf "%s/%s\n" "$HOME" "${value#~/}"
      ;;
    *)
      printf "%s\n" "$value"
      ;;
  esac
}

config_value() {
  local key="$1"
  if [ ! -f "$RALPH_CONFIG_FILE" ]; then
    return 0
  fi
  jq -r --arg key "$key" '.[$key] // empty' "$RALPH_CONFIG_FILE" 2>/dev/null || true
}

normalize_positive_int() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
    printf "%s\n" "$value"
  else
    printf "%s\n" "$fallback"
  fi
}

resolve_openclaw_bin() {
  if command -v openclaw >/dev/null 2>&1; then
    command -v openclaw
    return 0
  fi

  local configured="${OPENCLAW_BIN:-$(config_value openclaw_bin)}"
  configured="$(expand_tilde "$configured")"

  if [ -n "$configured" ] && [ -x "$configured" ]; then
    printf "%s\n" "$configured"
    return 0
  fi

  for candidate in /opt/homebrew/bin/openclaw /usr/local/bin/openclaw /usr/bin/openclaw; do
    if [ -x "$candidate" ]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  printf "\n"
}

detect_gateway_port() {
  if [ -n "${OPENCLAW_GATEWAY_PORT:-}" ]; then
    printf "%s\n" "$OPENCLAW_GATEWAY_PORT"
    return 0
  fi

  local cfg_port
  cfg_port="$(config_value gateway_port)"
  if [[ "$cfg_port" =~ ^[0-9]+$ ]]; then
    printf "%s\n" "$cfg_port"
    return 0
  fi

  local openclaw_config="${OPENCLAW_CONFIG_FILE:-$HOME/.openclaw/openclaw.json}"
  if [ -f "$openclaw_config" ]; then
    local detected
    detected="$(jq -r '.gateway.port // .gateway.ws.port // .gateway.websocket.port // .server.port // .port // empty' "$openclaw_config" 2>/dev/null || true)"
    if [[ "$detected" =~ ^[0-9]+$ ]]; then
      printf "%s\n" "$detected"
      return 0
    fi
  fi

  printf "3117\n"
}

hash_output() {
  local text="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf "%s" "$text" | shasum | awk '{print $1}'
  else
    printf "%s" "$text" | sha1sum | awk '{print $1}'
  fi
}

if [ -f "$RALPH_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$RALPH_ENV_FILE"
  set +a
fi

TMUX_SOCK="${RALPH_TMUX_SOCKET:-$(config_value tmux_socket)}"
TMUX_SOCK="${TMUX_SOCK:-$HOME/.tmux/sock}"
TMUX_SOCK="$(expand_tilde "$TMUX_SOCK")"

RALPH_BOT_TOKEN_ENV="${RALPH_BOT_TOKEN_ENV:-$(config_value telegram_bot_token_env)}"
RALPH_BOT_TOKEN_ENV="${RALPH_BOT_TOKEN_ENV:-TELEGRAM_BOT_TOKEN_AVA}"

RALPH_TELEGRAM_CHAT_ID="${RALPH_TELEGRAM_CHAT_ID:-$(config_value telegram_chat_id)}"

RALPH_STALL_THRESHOLD="${RALPH_STALL_THRESHOLD:-$(config_value stall_threshold)}"
RALPH_STALL_THRESHOLD="$(normalize_positive_int "${RALPH_STALL_THRESHOLD:-3}" 3)"

RALPH_CLEANUP_THRESHOLD="${RALPH_CLEANUP_THRESHOLD:-$(config_value cleanup_threshold)}"
RALPH_CLEANUP_THRESHOLD="$(normalize_positive_int "${RALPH_CLEANUP_THRESHOLD:-3}" 3)"

OPENCLAW_BIN="$(resolve_openclaw_bin)"
GATEWAY_PORT="$(detect_gateway_port)"

notify_telegram() {
  local text="$1"
  local token="${!RALPH_BOT_TOKEN_ENV:-}"

  if [ -n "$token" ] && [ -n "${RALPH_TELEGRAM_CHAT_ID:-}" ]; then
    curl -s "https://api.telegram.org/bot${token}/sendMessage" \
      -d "chat_id=${RALPH_TELEGRAM_CHAT_ID}" \
      -d "text=${text}" \
      -d "parse_mode=Markdown" \
      >/dev/null 2>&1 || true
  fi

  if [ -n "$OPENCLAW_BIN" ]; then
    "$OPENCLAW_BIN" system event --text "$text" --mode now >/dev/null 2>&1 || true
  fi
}

[ -f "$RALPH_STATE_FILE" ] || echo '{}' > "$RALPH_STATE_FILE"

[ -S "$TMUX_SOCK" ] || exit 0

SESSIONS=$(tmux -S "$TMUX_SOCK" list-sessions -F '#{session_name}' 2>/dev/null) || exit 0
[ -z "$SESSIONS" ] && exit 0

STATE=$(cat "$RALPH_STATE_FILE")
UPDATED_STATE="$STATE"

while IFS= read -r SESSION; do
  OUTPUT=$(tmux -S "$TMUX_SOCK" capture-pane -t "$SESSION" -p 2>/dev/null | tail -40)
  [ -z "$OUTPUT" ] && continue

  echo "$OUTPUT" | grep -qE '\[INFO\] (Task|Starting Ralphy)|EXITED:|ralphy' || continue

  HASH="$(hash_output "$OUTPUT")"

  PREV_HASH=$(echo "$STATE" | jq -r --arg s "$SESSION" '.[$s].hash // ""')
  PREV_STALLS=$(echo "$STATE" | jq -r --arg s "$SESSION" '.[$s].stalls // 0')
  ALREADY_NOTIFIED=$(echo "$STATE" | jq -r --arg s "$SESSION" '.[$s].notified // false')

  if echo "$OUTPUT" | grep -q 'EXITED:'; then
    EXIT_CODE=$(echo "$OUTPUT" | grep -o 'EXITED: [0-9]*' | tail -1 | awk '{print $2}')
    if [ "$ALREADY_NOTIFIED" != "true" ]; then
      REPO=$(tmux -S "$TMUX_SOCK" display-message -t "$SESSION" -p '#{pane_current_path}' 2>/dev/null || echo "unknown")
      REPO_NAME=$(basename "$REPO")

      if [ "$EXIT_CODE" = "0" ]; then
        notify_telegram "Ralph complete: \`${SESSION}\` finished successfully in \`${REPO_NAME}\`."
      else
        notify_telegram "Ralph finished with errors: \`${SESSION}\` (exit ${EXIT_CODE}) in \`${REPO_NAME}\`."
      fi

      if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ] && [ -n "${GATEWAY_PORT:-}" ]; then
        curl -s -X POST "http://127.0.0.1:${GATEWAY_PORT}/api/cron/wake" \
          -H "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN}" \
          -H "Content-Type: application/json" \
          -d "{\"text\":\"RALPH POST-COMPLETION: Session '${SESSION}' finished (exit ${EXIT_CODE}) in ${REPO}. Run the Post-Completion Protocol from AGENTS.md now.\",\"mode\":\"now\"}" \
          >/dev/null 2>&1 || true
      fi

      UPDATED_STATE=$(echo "$UPDATED_STATE" | jq --arg s "$SESSION" --arg h "$HASH" '.[$s] = {"hash": $h, "stalls": 0, "notified": true, "dead_checks": 0}')
    fi
    continue
  fi

  if [ "$HASH" = "$PREV_HASH" ]; then
    NEW_STALLS=$((PREV_STALLS + 1))
    UPDATED_STATE=$(echo "$UPDATED_STATE" | jq --arg s "$SESSION" --arg h "$HASH" --argjson st "$NEW_STALLS" '.[$s] = {"hash": $h, "stalls": $st, "notified": false}')

    if [ "$NEW_STALLS" -ge "$RALPH_STALL_THRESHOLD" ] && [ $((NEW_STALLS % 3)) -eq 0 ]; then
      STALL_MINS=$((NEW_STALLS * 10))
      notify_telegram "Ralph stalled: \`${SESSION}\` no output change for about ${STALL_MINS} minutes."
    fi
  else
    UPDATED_STATE=$(echo "$UPDATED_STATE" | jq --arg s "$SESSION" --arg h "$HASH" '.[$s] = {"hash": $h, "stalls": 0, "notified": false}')
  fi
done <<< "$SESSIONS"

while IFS= read -r SESSION; do
  [ -z "$SESSION" ] && continue
  NOTIFIED=$(echo "$UPDATED_STATE" | jq -r --arg s "$SESSION" '.[$s].notified // false')
  DEAD_CHECKS=$(echo "$UPDATED_STATE" | jq -r --arg s "$SESSION" '.[$s].dead_checks // 0')

  if [ "$NOTIFIED" = "true" ]; then
    NEW_DEAD=$((DEAD_CHECKS + 1))
    UPDATED_STATE=$(echo "$UPDATED_STATE" | jq --arg s "$SESSION" --argjson dc "$NEW_DEAD" '.[$s].dead_checks = $dc')

    if [ "$NEW_DEAD" -ge "$RALPH_CLEANUP_THRESHOLD" ]; then
      tmux -S "$TMUX_SOCK" kill-session -t "$SESSION" 2>/dev/null || true
      UPDATED_STATE=$(echo "$UPDATED_STATE" | jq --arg s "$SESSION" 'del(.[$s])')
    fi
  fi
done <<< "$SESSIONS"

for KEY in $(echo "$UPDATED_STATE" | jq -r 'keys[]'); do
  if ! echo "$SESSIONS" | grep -qx "$KEY"; then
    UPDATED_STATE=$(echo "$UPDATED_STATE" | jq --arg s "$KEY" 'del(.[$s])')
  fi
done

echo "$UPDATED_STATE" > "$RALPH_STATE_FILE"
