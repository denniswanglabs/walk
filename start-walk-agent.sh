#!/bin/bash
# start-walkthrough-agent.sh
#
# One-tap bring-up of the entire Walk Agent stack after a reboot.
# Ordered, with readiness gates between each layer so nothing races:
#
#   Docker → NemoClaw gateway/sandbox (recover) → host servers → poll.sh
#
# Idempotent: safe to run twice. Kills stale listeners/pollers first.
# NEVER rebuilds the sandbox (destructive) — only `recover` (safe).

set -uo pipefail

PROJECT="$HOME/Desktop/Projects/Hackathons/walk"
OBSERVE="$PROJECT/explainer-agent/observe-host"
NEMOCLAW="$HOME/.local/bin/nemoclaw"
[ -x "$NEMOCLAW" ] || NEMOCLAW="nemoclaw"

# NVIDIA_API_KEY + PATH live in .zshrc — a double-clicked .command does NOT
# source it automatically. Required for `nemoclaw recover` + inference.
source "$HOME/.zshrc" 2>/dev/null || true

# Don't let better-opn pop "Where is Arc?" dialogs at startup.
export BROWSER=none

say() { printf "\n\033[1;32m▸ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m  ! %s\033[0m\n" "$1"; }

echo "════════════════════════════════════════════════"
echo "  Walk Agent — stack bring-up"
echo "════════════════════════════════════════════════"

# ---------------------------------------------------------------------------
# 1. Docker Desktop
# ---------------------------------------------------------------------------
say "1/5  Docker Desktop"
if docker info >/dev/null 2>&1; then
  echo "  already up"
else
  echo "  launching Docker Desktop..."
  open -a Docker
  for i in $(seq 1 40); do
    if docker info >/dev/null 2>&1; then echo "  up after ~$((i*3))s"; break; fi
    sleep 3
  done
  docker info >/dev/null 2>&1 || { warn "Docker still down after 120s — open it manually and re-run."; exit 1; }
fi

# ---------------------------------------------------------------------------
# 2. NemoClaw gateway + sandbox (recover — never rebuild)
# ---------------------------------------------------------------------------
say "2/5  NemoClaw gateway + sandbox (recover)"
if "$NEMOCLAW" promo-agent exec --no-tty -- true >/dev/null 2>&1; then
  echo "  sandbox already reachable"
else
  echo "  running recover (this can take a minute)..."
  "$NEMOCLAW" promo-agent recover 2>&1 | tail -4
  echo "  waiting for sandbox exec to succeed..."
  # Gate on `exec true`, NOT Docker's healthcheck — the container healthcheck
  # reports "unhealthy" even when exec works fine.
  for i in $(seq 1 40); do
    if "$NEMOCLAW" promo-agent exec --no-tty -- true >/dev/null 2>&1; then
      echo "  sandbox reachable after ~$((i*3))s"; break
    fi
    sleep 3
  done
  "$NEMOCLAW" promo-agent exec --no-tty -- true >/dev/null 2>&1 \
    || warn "sandbox not reachable — dashboard will load but live frame won't stream. Try: nemoclaw promo-agent recover"
fi

# ---------------------------------------------------------------------------
# 3. Re-stage /tmp/rewrite-log.py (wiped on reboot — repo copy is canonical)
# ---------------------------------------------------------------------------
say "3/5  staging helper scripts"
if [ -f "$PROJECT/explainer-agent/rewrite-log.py" ]; then
  cp -f "$PROJECT/explainer-agent/rewrite-log.py" /tmp/rewrite-log.py
  echo "  /tmp/rewrite-log.py restored"
fi

# ---------------------------------------------------------------------------
# 4. Host servers — kill stale, start fresh (idempotent)
# ---------------------------------------------------------------------------
say "4/5  dashboard servers"
# Free the ports if something stale is holding them
for port in 8081 8082; do
  pid=$(lsof -nP -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)
  [ -n "$pid" ] && { echo "  killing stale listener on :$port (pid $pid)"; kill "$pid" 2>/dev/null; }
done
# poll.sh runs as `bash poll.sh` (cwd not in cmdline), so match that pattern.
pkill -f "bash poll.sh" 2>/dev/null && echo "  killed stale poll.sh"
sleep 1

echo "  starting Flask API :8082"
( cd "$OBSERVE/dashboard" && BROWSER=none nohup python3 server.py > /tmp/dashboard-server.log 2>&1 & )

echo "  starting static dashboard :8081"
( cd "$OBSERVE/public" && nohup python3 -m http.server 8081 --bind 127.0.0.1 > /tmp/dashboard-static.log 2>&1 & )

echo "  starting poll.sh (live frame + log mirror)"
( cd "$OBSERVE" && nohup bash poll.sh > /tmp/poll.log 2>&1 & )

sleep 3

# ---------------------------------------------------------------------------
# 5. Verify + open
# ---------------------------------------------------------------------------
say "5/5  verify"
ok=1
curl -sS -o /dev/null --max-time 4 http://127.0.0.1:8081/ && echo "  :8081 OK" || { warn ":8081 not responding"; ok=0; }
curl -sS -o /dev/null --max-time 4 http://127.0.0.1:8082/api/health && echo "  :8082 OK" || { warn ":8082 not responding"; ok=0; }

if [ "$ok" = "1" ]; then
  open -a Safari "http://127.0.0.1:8081/"
  echo ""
  echo "════════════════════════════════════════════════"
  echo "  ✓ Walk Agent is UP — opened in Safari"
  echo "    http://127.0.0.1:8081/"
  echo "════════════════════════════════════════════════"
else
  echo ""
  warn "Some services didn't come up. Logs:"
  echo "    Flask:  /tmp/dashboard-server.log"
  echo "    Static: /tmp/dashboard-static.log"
  echo "    Poll:   /tmp/poll.log"
fi

echo ""
echo "(You can close this window.)"
