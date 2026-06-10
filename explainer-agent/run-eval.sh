#!/bin/bash
# Usage: run-eval.sh "<goal>" "<url>" <n_attempts> <variant_label> [<result_dir>]
# Runs N attempts, captures action-log + screenshots per attempt, scores each.
# Output: per-attempt JSON + aggregate report.
#
# Scoring: an attempt succeeds when the action-log shows the agent reached
# at_destination=true (final judgement). steps = action count.
#
# Notes:
#   - Stale sandbox node/chrome procs are killed before each attempt.
#   - make-explainer.sh is run with timeout 600s per attempt.
#   - The action-log is pulled from /sandbox/explainer-agent/run/action-log.json
#     (the canonical path produced by run.sh after a successful navigation).
#   - This harness does NOT render Remotion output — Phase A only measures
#     agent navigation success; rendering happens downstream.

set -u

GOAL="${1:?usage: $0 <goal> <url> [n] [label] [result_dir]}"
URL="${2:?usage: $0 <goal> <url> [n] [label] [result_dir]}"
N="${3:-5}"
LABEL="${4:-baseline}"
RESULT_DIR="${5:-/tmp/eval-$LABEL-$(date +%s)}"

# Default BEAM mode and step budget — overridable from the environment.
BEAM="${BEAM:-0}"
MAX_STEPS="${MAX_STEPS:-12}"

# Per-attempt wall budget. Must exceed make-explainer.sh's own NEMOCLAW_TIMEOUT
# (900s default, 1800s when BEAM=1) plus render time, otherwise we kill while
# the agent is mid-flight.
if [ "$BEAM" = "1" ]; then
  ATTEMPT_TIMEOUT="${ATTEMPT_TIMEOUT:-2100}"
else
  ATTEMPT_TIMEOUT="${ATTEMPT_TIMEOUT:-1100}"
fi

PROJECT_ROOT="$HOME/Desktop/Projects/Hackathons/walk"
NEMOCLAW="$HOME/.local/bin/nemoclaw"
if [ ! -x "$NEMOCLAW" ]; then NEMOCLAW="nemoclaw"; fi

mkdir -p "$RESULT_DIR"
echo "[eval] goal=\"$GOAL\" url=\"$URL\" n=$N label=$LABEL beam=$BEAM max_steps=$MAX_STEPS"
echo "[eval] result_dir=$RESULT_DIR"

# Make sure jq exists for scoring; if missing, fall back to python3.
have_jq=0
if command -v jq >/dev/null 2>&1; then have_jq=1; fi

# Portable timeout — macOS has no `timeout`. Try gtimeout (coreutils), then
# fall back to a perl alarm wrapper. Both honour signal semantics well enough
# for our 600s budget.
run_with_timeout () {
  local seconds="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    perl -e 'use POSIX; my $t=shift; my $pid=fork(); if($pid==0){exec @ARGV or die;} my $deadline=time+$t; while(time<$deadline){my $r=waitpid($pid,POSIX::WNOHANG()); if($r==$pid){exit($?>>8);} sleep 1;} kill 9,$pid; exit 124;' "$seconds" "$@"
  fi
}

score_log () {
  local f="$1"
  if [ ! -s "$f" ]; then echo "false 0"; return; fi
  if [ $have_jq -eq 1 ]; then
    local reached steps
    reached=$(jq -r '
      def lastj: (.actions // []) | map(.judge // .judgement // {}) | last // {};
      def reached:
        ((.actions // []) | map(.judge // .judgement // {}) | map(.at_destination == true) | any) or
        ((.actions // []) | map(.kind // "") | map(. == "done") | any);
      if reached then "true" else "false" end
    ' "$f" 2>/dev/null || echo "false")
    steps=$(jq -r '(.actions // []) | length' "$f" 2>/dev/null || echo "0")
    echo "$reached $steps"
  else
    python3 - "$f" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    actions = d.get("actions", []) or []
    reached = any(((a.get("judge") or a.get("judgement") or {}).get("at_destination") is True) for a in actions) \
        or any((a.get("kind") == "done") for a in actions)
    print(("true" if reached else "false"), len(actions))
except Exception:
    print("false 0")
PY
  fi
}

for i in $(seq 1 "$N"); do
  echo "[eval] attempt $i/$N"

  # Kill stale sandbox procs AND wipe the previous run dir so we never score
  # against stale action-log.json from an earlier attempt.
  "$NEMOCLAW" promo-agent exec --no-tty -- bash -c 'pkill -9 node 2>/dev/null; pkill -9 chrome 2>/dev/null; sleep 2; rm -rf /sandbox/explainer-agent/run; true' >/dev/null 2>&1 || true

  ATTEMPT_LOG="$RESULT_DIR/attempt-$i.log"
  ACTION_LOG="$RESULT_DIR/attempt-$i.action-log.json"
  SUMMARY="$RESULT_DIR/attempt-$i.summary.json"

  cd "$PROJECT_ROOT"

  # Retry transient failures once (network / 429); skip render step by capping
  # what we keep — make-explainer.sh DOES render, but we accept the cost since
  # the harness needs to exercise the full path.
  EXIT=1
  for try in 1 2; do
    BEAM="$BEAM" run_with_timeout "$ATTEMPT_TIMEOUT" \
      ./explainer-agent/make-explainer.sh "$GOAL" "$URL" "$MAX_STEPS" \
      > "$ATTEMPT_LOG" 2>&1
    EXIT=$?
    if [ "$EXIT" -eq 0 ]; then break; fi
    # Retry only if the log looks like a transient (HTTP 429, network reset, timeout).
    if grep -Eqi '429|ETIMEDOUT|ECONNRESET|EAI_AGAIN|EPIPE|timed out' "$ATTEMPT_LOG"; then
      echo "[eval] attempt $i: transient failure (try $try); retrying"
      sleep 5
      continue
    fi
    break
  done

  # Pull the action-log even on failure — partial data is informative.
  "$NEMOCLAW" promo-agent exec --no-tty -- cat /sandbox/explainer-agent/run/action-log.json \
    > "$ACTION_LOG" 2>/dev/null || true
  if [ ! -s "$ACTION_LOG" ]; then
    echo '{"actions":[]}' > "$ACTION_LOG"
  fi

  read REACHED STEPS < <(score_log "$ACTION_LOG")
  REACHED="${REACHED:-false}"
  STEPS="${STEPS:-0}"

  echo "[eval] attempt $i: exit=$EXIT reached=$REACHED steps=$STEPS"

  cat > "$SUMMARY" <<EOF
{"attempt": $i, "exit_code": $EXIT, "at_destination": $REACHED, "steps": $STEPS, "label": "$LABEL", "goal": "$GOAL", "url": "$URL"}
EOF
done

# Aggregate
SUCCESS_COUNT=0
TOTAL_STEPS=0
for f in "$RESULT_DIR"/attempt-*.summary.json; do
  [ -s "$f" ] || continue
  if grep -q '"at_destination": true' "$f"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  fi
  if [ $have_jq -eq 1 ]; then
    s=$(jq -r '.steps // 0' "$f" 2>/dev/null)
  else
    s=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("steps",0))' "$f" 2>/dev/null)
  fi
  TOTAL_STEPS=$((TOTAL_STEPS + ${s:-0}))
done

if [ "$N" -gt 0 ]; then
  RATE=$(python3 -c "print(round($SUCCESS_COUNT / $N, 3))")
  AVG_STEPS=$(python3 -c "print(round($TOTAL_STEPS / $N, 2))")
else
  RATE=0
  AVG_STEPS=0
fi

cat > "$RESULT_DIR/aggregate.json" <<EOF
{
  "label": "$LABEL",
  "goal": "$GOAL",
  "url": "$URL",
  "n": $N,
  "successes": $SUCCESS_COUNT,
  "success_rate": $RATE,
  "avg_steps": $AVG_STEPS,
  "beam": "$BEAM",
  "max_steps": $MAX_STEPS,
  "result_dir": "$RESULT_DIR"
}
EOF

cat "$RESULT_DIR/aggregate.json"
