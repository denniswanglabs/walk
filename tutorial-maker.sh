#!/bin/bash
# tutorial-maker.sh
#
# URL + goal in, polished tutorial MP4 out.
# Composes auto-allowlist.sh + make-explainer.sh (BEAM=1) + replay-60fps.js +
# render-auto-overlay.sh into a single command.
#
# Usage:
#   tutorial-maker.sh <url> <goal> [output_mp4]
#
# Output:
#   - Polished MP4 at $3 (default ~/Downloads/tutorial-<epoch>.mp4)
#   - Workdir at /tmp/tutorial-<epoch>/ with intermediate artifacts

set -euo pipefail

URL="${1:-}"
GOAL="${2:-}"

if [ -z "$URL" ] || [ -z "$GOAL" ]; then
  echo "Usage: tutorial-maker.sh <url> <goal> [output_mp4]" >&2
  exit 1
fi

EPOCH=$(date +%s)
OUT="${3:-$HOME/Downloads/tutorial-$EPOCH.mp4}"

PROJECT="$HOME/Desktop/Projects/Hackathons/promo-agent"
WORKDIR="/tmp/tutorial-$EPOCH"
mkdir -p "$WORKDIR"

# Always resolve OUT to absolute.
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT="$OUT_DIR/$(basename "$OUT")"

NEMOCLAW="$HOME/.local/bin/nemoclaw"
if [ ! -x "$NEMOCLAW" ]; then NEMOCLAW="nemoclaw"; fi

echo "============================================================"
echo "  tutorial-maker"
echo "  URL:     $URL"
echo "  Goal:    $GOAL"
echo "  Workdir: $WORKDIR"
echo "  Output:  $OUT"
echo "============================================================"

# Step 1: Auto-allowlist the URL host + likely subresources.
echo
echo "[tutorial-maker] Step 1/4: Auto-allowlisting host..."
if ! bash "$PROJECT/explainer-agent/auto-allowlist.sh" "$URL" 2>&1 | tee "$WORKDIR/allowlist.log"; then
  echo "[tutorial-maker] FAILED at allowlist step. See $WORKDIR/allowlist.log" >&2
  exit 1
fi

# Step 2: NemoClaw agent run. BEAM=1 = multi-tab on; BEAM_K=2 = 2 scouts.
# grid.html populates with 2 parallel scout tabs Dennis can watch during the
# run. make-explainer.sh uses BEAM as a strict mode-toggle ([ "$BEAM" = "1" ])
# and BEAM_K as the scout count — must pass both.
# K dropped 4→2: NemoClaw sandbox hardcodes RLIMIT_NPROC=512; K=4 hits
# pthread_create EAGAIN during the observe-snapshot burst.
BEAM="${BEAM:-1}"
BEAM_K="${BEAM_K:-2}"
echo
echo "[tutorial-maker] Step 2/4: NemoClaw agent run (BEAM=$BEAM BEAM_K=$BEAM_K)..."
cd "$PROJECT"

set +e
BEAM="$BEAM" BEAM_K="$BEAM_K" OPEN_RESULT=0 NEMOCLAW_TIMEOUT="${NEMOCLAW_TIMEOUT:-900}" \
  ./explainer-agent/make-explainer.sh "$GOAL" "$URL" 15 \
  > "$WORKDIR/agent.log" 2>&1
AGENT_EXIT=$?
set -e

if [ "$AGENT_EXIT" -ne 0 ]; then
  echo "[tutorial-maker] Agent exited $AGENT_EXIT. Last 20 lines of log:"
  tail -20 "$WORKDIR/agent.log"
fi

# CANONICAL EXPLAINER PATH: if make-explainer.sh's inner Remotion render
# produced an `out-*.mp4` (Explainer composition — the style Dennis confirmed
# as canonical in `feedback_canonical_explainer_agent_video_format`), copy it
# to $OUT and exit. Skip Steps 3-4 (AutoOverlay) entirely. Falls through to
# the AutoOverlay path only if the Explainer render didn't succeed.
#
# IMPORTANT: this grep pipeline returns non-zero exit when there's no match,
# which `set -euo pipefail` propagates and silently kills the whole script.
# Wrap with set +e / set -e or trail with `|| true` to keep tutorial-maker
# alive when make-explainer's Remotion step fails.
set +e
EXPLAINER_OUT=$(grep "^DONE. Video: " "$WORKDIR/agent.log" 2>/dev/null | tail -1 | sed 's/^DONE. Video: //')
set -e
if [ -n "$EXPLAINER_OUT" ] && [ -s "$EXPLAINER_OUT" ]; then
  echo "[tutorial-maker] Canonical Explainer render found: $EXPLAINER_OUT"
  cp "$EXPLAINER_OUT" "$OUT"
  echo
  echo "============================================================"
  echo "[tutorial-maker] DONE  (canonical Explainer composition)"
  echo "  Output:  $OUT"
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe -v error -select_streams v -show_entries stream=avg_frame_rate,width,height,duration "$OUT" 2>&1 \
      | grep -E "width|height|duration|frame_rate" \
      | sed 's/^/  /'
  fi
  SIZE=$(ls -la "$OUT" | awk '{print $5}')
  echo "  Size:    $SIZE bytes"
  echo "  Workdir: $WORKDIR"
  echo "============================================================"
  exit 0
fi

echo "[tutorial-maker] No canonical Explainer output found — falling back to AutoOverlay (Steps 3-4)."

# Pull action-log (always — partial data is informative).
"$NEMOCLAW" promo-agent exec --no-tty -- cat /sandbox/explainer-agent/run/action-log.json \
  > "$WORKDIR/action-log.json" 2>/dev/null || echo '{"actions":[]}' > "$WORKDIR/action-log.json"

ACTION_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("actions",[])))' "$WORKDIR/action-log.json" 2>/dev/null || echo "0")
REACHED=$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
acts=d.get("actions",[]) or []
reached = any(((a.get("judge") or a.get("judgement") or {}).get("at_destination") is True) for a in acts) or any((a.get("kind")=="done") for a in acts)
print("true" if reached else "false")
' "$WORKDIR/action-log.json" 2>/dev/null || echo "false")

echo "[tutorial-maker] Agent actions: $ACTION_COUNT  reached: $REACHED"

if [ "$ACTION_COUNT" -lt 1 ]; then
  echo "[tutorial-maker] FAILED: no actions recorded. Cannot produce video." >&2
  echo "[tutorial-maker] See $WORKDIR/agent.log"
  exit 2
fi

if [ "$REACHED" != "true" ]; then
  echo "[tutorial-maker] WARNING: agent did not reach destination. Producing partial video."
fi

# Step 3: Host-side replay at native 1440p 60fps.
echo
echo "[tutorial-maker] Step 3/4: Replaying at native 1440p 60fps..."
cd "$PROJECT/explainer-agent/performer-v11"
set +e
node ./replay-60fps.js \
  --log "$WORKDIR/action-log.json" \
  --out "$WORKDIR/base.mp4" \
  > "$WORKDIR/replay.log" 2>&1
REPLAY_EXIT=$?
set -e

if [ "$REPLAY_EXIT" -ne 0 ] || [ ! -s "$WORKDIR/base.mp4" ]; then
  echo "[tutorial-maker] Replay failed (exit=$REPLAY_EXIT)." >&2
  echo "[tutorial-maker] Last 20 lines of replay log:"
  tail -20 "$WORKDIR/replay.log"
  exit 3
fi

BASE_SIZE=$(ls -la "$WORKDIR/base.mp4" | awk '{print $5}')
echo "[tutorial-maker] Replay done: $WORKDIR/base.mp4 ($BASE_SIZE bytes)"

# Step 4: Auto-overlay + final render. Fall back to base video if overlay missing.
echo
echo "[tutorial-maker] Step 4/4: Auto-overlay + render..."
if [ -x "$PROJECT/explainer-agent/render-auto-overlay.sh" ]; then
  set +e
  bash "$PROJECT/explainer-agent/render-auto-overlay.sh" \
    "$WORKDIR/action-log.json" \
    "$WORKDIR/base.mp4" \
    "$GOAL" \
    "$OUT" \
    > "$WORKDIR/overlay.log" 2>&1
  OVERLAY_EXIT=$?
  set -e

  if [ "$OVERLAY_EXIT" -ne 0 ] || [ ! -s "$OUT" ]; then
    echo "[tutorial-maker] Overlay render failed (exit=$OVERLAY_EXIT). Falling back to base video."
    echo "[tutorial-maker] Last 30 lines of overlay log:"
    tail -30 "$WORKDIR/overlay.log"
    cp "$WORKDIR/base.mp4" "$OUT"
  fi
else
  echo "[tutorial-maker] render-auto-overlay.sh missing — shipping base video as final."
  cp "$WORKDIR/base.mp4" "$OUT"
fi

# Summary.
echo
echo "============================================================"
echo "[tutorial-maker] DONE"
echo "  Output: $OUT"
if command -v ffprobe >/dev/null 2>&1; then
  ffprobe -v error -select_streams v -show_entries stream=avg_frame_rate,r_frame_rate,width,height,duration "$OUT" 2>&1 \
    | grep -E "width|height|duration|frame_rate" \
    | sed 's/^/  /'
fi
SIZE=$(ls -la "$OUT" | awk '{print $5}')
echo "  Size: $SIZE bytes"
echo "  Workdir (intermediates): $WORKDIR"
echo "============================================================"
