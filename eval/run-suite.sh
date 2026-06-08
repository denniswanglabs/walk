#!/bin/bash
# eval/run-suite.sh — run the Walk eval suite over every target in targets.json.
# Per attempt records: independent navigation success (URL/title), step count,
# wall-clock seconds, failure category. Aggregates per target + suite-wide.
# Render is skipped (SKIP_RENDER=1) — Phase A measures navigation only.
#
# Usage:   eval/run-suite.sh <label> [n_attempts] [targets_json]
# Example: eval/run-suite.sh baseline-super 3
# Env:     MODEL (passed to make-explainer.sh; default = sandbox's current),
#          BEAM (default 0), ATTEMPT_TIMEOUT (default 1100s).

set -u

LABEL="${1:?usage: run-suite.sh <label> [n] [targets_json]}"
N="${2:-3}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TARGETS="${3:-$HERE/targets.json}"
PROJECT_ROOT="$(cd "$HERE/.." && pwd)"
EXPLAINER="$PROJECT_ROOT/explainer-agent"
NEMOCLAW="$HOME/.local/bin/nemoclaw"; [ -x "$NEMOCLAW" ] || NEMOCLAW="nemoclaw"

BEAM="${BEAM:-0}"
ATTEMPT_TIMEOUT="${ATTEMPT_TIMEOUT:-1100}"
STAMP=$(date +%Y%m%d-%H%M%S)
RESULT_DIR="$HERE/results/$LABEL-$STAMP"
mkdir -p "$RESULT_DIR"

run_with_timeout () {
  local seconds="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$seconds" "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"
  else
    perl -e 'use POSIX; my $t=shift; my $pid=fork(); if($pid==0){exec @ARGV or die;} my $d=time+$t; while(time<$d){my $r=waitpid($pid,POSIX::WNOHANG()); if($r==$pid){exit($?>>8);} sleep 1;} kill 9,$pid; exit 124;' "$seconds" "$@"
  fi
}

mapfile -t TARGET_LINES < <(python3 -c 'import json,sys
for t in json.load(open(sys.argv[1])): print(json.dumps(t))' "$TARGETS")

echo "[suite] label=$LABEL n=$N beam=$BEAM model=${MODEL:-<sandbox-default>} targets=${#TARGET_LINES[@]}"
echo "[suite] result_dir=$RESULT_DIR"

for TJSON in "${TARGET_LINES[@]}"; do
  TID=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["id"])' "$TJSON")
  URL=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["url"])' "$TJSON")
  GOAL=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["goal"])' "$TJSON")
  MAX_STEPS=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("max_steps",12))' "$TJSON")
  echo "[suite] === target=$TID ==="

  for i in $(seq 1 "$N"); do
    # Kill stale sandbox procs + wipe prior run dir so we never score stale logs.
    "$NEMOCLAW" promo-agent exec --no-tty -- bash -c \
      'pkill -9 node 2>/dev/null; pkill -9 chrome 2>/dev/null; sleep 2; rm -rf /sandbox/explainer-agent/run; true' \
      >/dev/null 2>&1 || true

    ATTEMPT_LOG="$RESULT_DIR/$TID-$i.log"
    ACTION_LOG="$RESULT_DIR/$TID-$i.action-log.json"
    RESULT_JSON="$RESULT_DIR/$TID-$i.result.json"

    cd "$PROJECT_ROOT"
    T0=$(date +%s)
    SKIP_RENDER=1 BEAM="$BEAM" MODEL="${MODEL:-}" run_with_timeout "$ATTEMPT_TIMEOUT" \
      "$EXPLAINER/make-explainer.sh" "$GOAL" "$URL" "$MAX_STEPS" \
      > "$ATTEMPT_LOG" 2>&1
    EXIT=$?
    T1=$(date +%s)
    WALL=$((T1 - T0))

    "$NEMOCLAW" promo-agent exec --no-tty -- cat /sandbox/explainer-agent/run/action-log.json \
      > "$ACTION_LOG" 2>/dev/null || true
    [ -s "$ACTION_LOG" ] || echo '{"actions":[]}' > "$ACTION_LOG"

    python3 "$HERE/score.py" "$ACTION_LOG" "$TJSON" "$EXIT" "$WALL" "$ATTEMPT_LOG" \
      | python3 -c 'import json,sys
d=json.load(sys.stdin); d["target"]=sys.argv[1]; d["attempt"]=int(sys.argv[2]); print(json.dumps(d))' \
      "$TID" "$i" > "$RESULT_JSON"

    echo "[suite] $TID #$i: $(cat "$RESULT_JSON")"
  done
done

python3 "$HERE/report.py" "$RESULT_DIR" "$LABEL" > "$RESULT_DIR/report.json"
echo
echo "[suite] ===== REPORT ====="
cat "$RESULT_DIR/report.json"
echo
echo "[suite] done → $RESULT_DIR/report.json"
