#!/bin/bash
# make-explainer.sh — give the NemoClaw agent a prompt + URL,
# get back a rendered explainer video.
#
# Usage:
#   ./make-explainer.sh "Find the installation command for the Card component"
#   ./make-explainer.sh "Find Sonner install" "https://ui.shadcn.com"
#   ./make-explainer.sh "Find docs about Server Components" "https://nextjs.org"
#   ./make-explainer.sh "Find docs about X" "https://example.com" 20

set -euo pipefail

GOAL="${1:?usage: $0 \"<goal>\" [start_url] [max_steps]}"
START_URL="${2:-https://ui.shadcn.com}"
MAX_STEPS="${3:-20}"

# BEAM=1 enables Tier 1 multi-tab beam search with pre-click ranking + Cmd+K
# search scout. Default OFF for backward compat with v13 single-tab loop.
BEAM="${BEAM:-0}"
BEAM_K="${BEAM_K:-2}"

# Beam mode is much heavier (K parallel browser contexts) — bump the sandbox
# timeout when it's on so long real-world goals don't trip the 900s default.
if [ "$BEAM" = "1" ]; then
  NEMOCLAW_TIMEOUT="${NEMOCLAW_TIMEOUT:-1800}"
else
  NEMOCLAW_TIMEOUT="${NEMOCLAW_TIMEOUT:-900}"
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
SLUG=$(echo "$GOAL" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-40)
TIMESTAMP=$(date +%H%M%S)
OUT_MP4="$HERE/out-$TIMESTAMP-$SLUG.mp4"

# v13: Nemotron-all-the-way-down. NVIDIA_API_KEY is the only key needed —
# action selection uses Nemotron-3-Super-120B, judging uses Nemotron-3-Nano-Omni.
# Both hit the same NIM endpoint with the same key.
if [ -z "${NVIDIA_API_KEY:-}" ]; then
  if [ -f "$HOME/.zshrc" ]; then
    set +u
    # shellcheck disable=SC1090
    source "$HOME/.zshrc" 2>/dev/null || true
    set -u
  fi
fi
if [ -z "${NVIDIA_API_KEY:-}" ]; then
  echo "ERROR: NVIDIA_API_KEY not set in env. Add it to ~/.zshrc."
  exit 1
fi

echo "============================================================"
echo "  Goal:       $GOAL"
echo "  Start URL:  $START_URL"
echo "  Max steps:  $MAX_STEPS  (includes backtracks)"
echo "  Mode:       BEAM=$BEAM${BEAM:+ K=$BEAM_K}"
echo "  Timeout:    ${NEMOCLAW_TIMEOUT}s"
echo "  Output:     $OUT_MP4"
echo "============================================================"
echo

echo "[1/4] Running agent in NemoClaw sandbox..."
~/.local/bin/nemoclaw promo-agent exec --no-tty --timeout "$NEMOCLAW_TIMEOUT" -- bash -c \
  "rm -rf /sandbox/explainer-agent/run && export GOAL=$(printf '%q' "$GOAL") && export START_URL=$(printf '%q' "$START_URL") && export MAX_STEPS=$MAX_STEPS && export BEAM=$BEAM && export BEAM_K=$BEAM_K && export NVIDIA_API_KEY=$(printf '%q' "$NVIDIA_API_KEY") && bash /sandbox/explainer-agent/run.sh" 2>&1 \
  | grep -E '^\[' | tail -80

echo
echo "[2/4] Pulling artifacts..."
cd "$HERE/remotion/public"
rm -rf screenshots-sandbox
mkdir -p screenshots-sandbox
~/.local/bin/nemoclaw promo-agent exec --no-tty -- cat /sandbox/explainer-agent/run/action-log.json > /tmp/sandbox-action-log.json 2>/dev/null
~/.local/bin/nemoclaw promo-agent exec --no-tty -- cat /sandbox/explainer-agent/run/attempted-log.json > /tmp/sandbox-attempted-log.json 2>/dev/null || true

ACTION_COUNT=$(python3 -c 'import json; print(len(json.load(open("/tmp/sandbox-action-log.json"))["actions"]))')
echo "  agent recorded $ACTION_COUNT filtered actions"

if [ "$ACTION_COUNT" -lt 1 ]; then
  echo "  ERROR: no actions recorded. Agent failed to navigate."
  exit 1
fi

# Pull only the filtered screenshots/ (NOT attempted-screenshots/).
files=$(~/.local/bin/nemoclaw promo-agent exec --no-tty -- ls /sandbox/explainer-agent/run/screenshots/ 2>/dev/null | tr -d '\r')
for f in $files; do
  ~/.local/bin/nemoclaw promo-agent exec --no-tty -- base64 "/sandbox/explainer-agent/run/screenshots/$f" 2>/dev/null | base64 -d > "screenshots-sandbox/$f"
done
echo "  pulled $(ls screenshots-sandbox | wc -l | tr -d ' ') screenshots"

python3 /tmp/rewrite-log.py > /dev/null
echo "  action-log rewritten (paths + synthetic done if needed)"

# Also copy attempted-log.json next to action-log so the watchdog can inspect
if [ -s /tmp/sandbox-attempted-log.json ]; then
  cp /tmp/sandbox-attempted-log.json "$HERE/remotion/public/attempted-log.json"
  echo "  attempted-log.json copied to remotion/public/"
fi

echo
if [ "${SKIP_RENDER:-0}" = "1" ]; then
  echo "[3/4] SKIP_RENDER=1 — skipping Remotion render (navigation-only run)."
  echo
  echo "DONE. Navigation complete (render skipped)."
  exit 0
fi

echo "[3/4] Rendering Remotion composition..."
cd "$HERE/remotion"
./node_modules/.bin/remotion render src/index.ts Explainer "$OUT_MP4" --concurrency=8 --log=error 2>&1 | tail -3

if [ ! -f "$OUT_MP4" ]; then
  echo "  ERROR: render failed."
  exit 1
fi

SIZE=$(ls -la "$OUT_MP4" | awk '{print $5}')
echo "  rendered: $OUT_MP4 ($SIZE bytes)"

echo
echo "[4/4] Opening in QuickTime..."
open "$OUT_MP4"

echo
echo "DONE. Video: $OUT_MP4"
