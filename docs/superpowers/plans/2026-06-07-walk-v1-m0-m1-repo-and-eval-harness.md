# Walk v1 — M0 (Repo Migration) + M1 (Eval Harness) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze the hackathon-winning repo, stand up a private `walk` product repo with full lineage, and build a suite eval harness that measures today's engine (baseline numbers) so all later hardening/model work is data-driven.

**Architecture:** Two milestones. **M0** is pure git + a tiny README edit — no engine code changes. **M1** adds a self-contained `eval/` harness (bash orchestrator + small testable Python scorer) that runs the EXISTING agent (`explainer-agent/make-explainer.sh`) over a list of targets, scores navigation success with an **independent URL/title assertion** read from `action-log.json`, records step count + wall-clock + a failure category, and aggregates a report. Render is skipped during eval (`SKIP_RENDER=1`) — Phase A measures navigation only.

**Tech Stack:** git + GitHub CLI (`gh`); bash; Python 3 (stdlib only, no new deps); the existing NemoClaw sandbox named `promo-agent`; Nemotron-3-Super-120B via NVIDIA NIM (unchanged in this plan).

**Scope note:** This is the first of several plans for the spec `docs/superpowers/specs/2026-06-07-walk-v1-hardening-design.md`. M2 (reliability hardening + security fix + canonicalization), M3 (Ultra A/B + model-flag plumbing), and M4 (speed pass) get their own plans once M1 produces a baseline — their tasks depend on what the harness reveals.

**Cross-repo facts the engineer must know:**
- The host scripts exec the agent INSIDE the NemoClaw sandbox (`nemoclaw promo-agent exec -- bash /sandbox/explainer-agent/run.sh`). Editing host files does NOT change what the sandbox runs. This plan deliberately does not touch the sandbox — M1 measures the sandbox agent as-is.
- `make-explainer.sh` resolves its own dir via `HERE`, so it is repo-relative and works from `walk`. `tutorial-maker.sh` hardcodes a `promo-agent` path (line 28) — NOT used by the harness; leave it for M2.
- The NemoClaw sandbox is named `promo-agent`. Keep that name for now (renaming is M2).

---

## File Structure

**M0 (in `~/Desktop/Projects/Hackathons/`):**
- `promo-agent/` — frozen. Only change: a new tag `v1.0-gtc-taipei-winner` (no commits to `main`).
- `walk/` — NEW full-history clone of `promo-agent`, origin re-pointed to a new private GitHub repo `denniswanglabs/walk`.
- `walk/.gitignore` — Modify/create: ignore `node_modules/`, render artifacts, `eval/results/`.
- `walk/README.md` — Modify: "Walkthrough Agent" → "Walk Agent".
- `walk/docs/superpowers/` — Create: copy the spec + this plan in (they're uncommitted in `promo-agent`).

**M1 (all new, in `walk/eval/`):**
- `walk/eval/targets.json` — the eval suite (id, url, goal, expectations).
- `walk/eval/score.py` — pure, testable scorer/classifier (success + steps + category).
- `walk/eval/test_score.py` — zero-dep unit tests for `score.py`.
- `walk/eval/fixtures/stripe-success.action-log.json` — test fixture.
- `walk/eval/report.py` — aggregates per-attempt result JSONs into a report.
- `walk/eval/run-suite.sh` — orchestrator: loop targets × N attempts, time + score, aggregate.
- `walk/explainer-agent/make-explainer.sh` — Modify: add `SKIP_RENDER` guard around the render step.
- `walk/eval/results/` — output dir (gitignored; holds baseline report).

---

## MILESTONE 0 — Repo Migration & Freeze

### Task M0.1: Freeze and tag the winning commit

**Files:** none (git only, in `promo-agent`).

- [ ] **Step 1: Confirm the winning commit is `acd4e49` and `main` is in sync**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/promo-agent
git fetch origin
git rev-parse HEAD
git rev-list --count origin/main..HEAD
```
Expected: HEAD prints a SHA starting `acd4e49…`; the count prints `0` (local == origin/main).

- [ ] **Step 2: Create the immutable fallback tag**

Run:
```bash
git tag -a v1.0-gtc-taipei-winner acd4e49 -m "NVIDIA GTC Taipei 2026 Agent Hackathon winning submission (frozen reference)"
```

- [ ] **Step 3: Push the tag**

Run:
```bash
git push origin v1.0-gtc-taipei-winner
```

- [ ] **Step 4: Verify the tag exists locally and on the remote**

Run:
```bash
git tag
git ls-remote --tags origin | grep v1.0-gtc-taipei-winner
```
Expected: `v1.0-gtc-taipei-winner` appears in both. **Do NOT commit the working-tree drift to `promo-agent`** — the frozen fallback is this tag; `main` stays untouched.

---

### Task M0.2: Create the private `walk` repo with full history

**Files:** new working copy `~/Desktop/Projects/Hackathons/walk/`.

- [ ] **Step 1: Verify `gh` is authenticated**

Run:
```bash
gh auth status
```
Expected: logged in as `denniswanglabs`. If not: `gh auth login` (do this interactively, then continue).

- [ ] **Step 2: Create the empty private repo**

Run:
```bash
gh repo create walk --private --description "Walk — autonomous URL+goal to walkthrough video (productization of the GTC-winning agent)"
```
Expected: prints `https://github.com/denniswanglabs/walk`.

- [ ] **Step 3: Make a full-history local clone from the frozen repo**

Run:
```bash
cd ~/Desktop/Projects/Hackathons
git clone ~/Desktop/Projects/Hackathons/promo-agent walk
```
Expected: `Cloning into 'walk'... done.` (This copies committed history only — NOT the uncommitted drift, which is what we want.)

- [ ] **Step 4: Re-point origin to the new GitHub repo and push history + lineage tag**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk
git remote remove origin
git remote add origin https://github.com/denniswanglabs/walk.git
git push -u origin main
git push origin v1.0-gtc-taipei-winner
```
Expected: `main` and the tag push successfully.

- [ ] **Step 5: Verify lineage is intact**

Run:
```bash
git log --oneline -3
git rev-parse v1.0-gtc-taipei-winner
git remote -v
```
Expected: same 3 commits ending `acd4e49`; the tag resolves to `acd4e49…`; origin points at `denniswanglabs/walk`.

---

### Task M0.3: Productization baseline commit (name, pruning, ignores, docs)

**Files:**
- Modify: `walk/README.md`
- Create: `walk/.gitignore`
- Remove: `walk/experiments/`, `walk/marketing-deprecated/`
- Create: `walk/docs/superpowers/specs/2026-06-07-walk-v1-hardening-design.md` and `walk/docs/superpowers/plans/2026-06-07-walk-v1-m0-m1-repo-and-eval-harness.md`

- [ ] **Step 1: Adopt the product name in the README**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk
sed -i '' 's/Walkthrough Agent/Walk Agent/g' README.md
grep -n "Walk Agent" README.md | head -3
```
Expected: the H1 / references now read "Walk Agent".

- [ ] **Step 2: Prune the deprecated trees the original had archived**

Run:
```bash
git rm -r --quiet experiments marketing-deprecated
```
Expected: those paths staged for deletion. (Leave `_archive/` — harmless reference.)

- [ ] **Step 3: Add `.gitignore` for build/run artifacts**

Append to `walk/.gitignore` (create if missing):
```gitignore
# build / run artifacts
node_modules/
explainer-agent/out-*.mp4
explainer-agent/**/screenshots-sandbox/
**/action-log.json
# eval outputs
eval/results/
```

- [ ] **Step 3b: Stop tracking artifacts that were committed in the original**

Run:
```bash
git rm -r --cached --quiet explainer-agent/remotion/node_modules 2>/dev/null || true
git rm --cached --quiet explainer-agent/remotion/public/action-log.json 2>/dev/null || true
```
Expected: these stop being tracked (now ignored). Errors are fine if they weren't tracked.

- [ ] **Step 4: Bring the design docs into `walk`**

Run:
```bash
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp ~/Desktop/Projects/Hackathons/promo-agent/docs/superpowers/specs/2026-06-07-walk-v1-hardening-design.md docs/superpowers/specs/
cp ~/Desktop/Projects/Hackathons/promo-agent/docs/superpowers/plans/2026-06-07-walk-v1-m0-m1-repo-and-eval-harness.md docs/superpowers/plans/
```

- [ ] **Step 5: Commit and push the baseline**

Run:
```bash
git add -A
git commit -m "chore: productization baseline — Walk Agent name, prune deprecated trees, ignore artifacts, add design docs"
git push
```
Expected: clean push to `walk`.

- [ ] **Step 6: Verify `walk` is self-consistent**

Run:
```bash
git status
ls explainer-agent/make-explainer.sh explainer-agent/run-eval.sh docs/superpowers/specs/ docs/superpowers/plans/
```
Expected: clean working tree; the engine scripts and both design docs are present.

---

## MILESTONE 1 — Eval Harness + Baseline

> All M1 work happens in `~/Desktop/Projects/Hackathons/walk`. Commit after each task.

### Task M1.1: Eval suite definition

**Files:**
- Create: `walk/eval/targets.json`

- [ ] **Step 1: Create the targets file**

Create `walk/eval/targets.json`:
```json
[
  {
    "id": "stripe-map-payment-data",
    "url": "https://docs.stripe.com/get-started",
    "goal": "Go to Get started, then Migrate to Stripe, then Migrate payment data, then click Map payment data and stop.",
    "max_steps": 12,
    "expect_url_contains": "map-payment-data"
  },
  {
    "id": "nemoclaw-install-macos",
    "url": "https://docs.nvidia.com/nemoclaw/latest/home",
    "goal": "Open the page that explains how to install the NemoClaw CLI on macOS.",
    "max_steps": 12,
    "expect_url_contains": "install"
  },
  {
    "id": "vercel-env-vars",
    "url": "https://vercel.com/docs",
    "goal": "Open the documentation page about environment variables.",
    "max_steps": 12,
    "expect_url_contains": "environment-variables"
  },
  {
    "id": "wikipedia-nvidia-first-gpu",
    "url": "https://en.wikipedia.org/wiki/Nvidia",
    "goal": "Navigate to the section about Nvidia's first graphics accelerator.",
    "max_steps": 12,
    "expect_url_contains": "Nvidia",
    "expect_title_contains": "Nvidia"
  }
]
```

> **Calibration note (not a placeholder):** `expect_url_contains` for `stripe-map-payment-data` is verified against a real run (final url ended `.../map-payment-data`). The others are best-effort; the harness prints `final_url` per attempt, so after the first run, tighten any expectation that didn't match the true destination. Wikipedia stays on one URL while scrolling, so its URL check is weak — `expect_title_contains` is the fallback; treat its success rate as soft until M2 adds a section-anchor check.

- [ ] **Step 2: Validate the JSON parses**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk
python3 -c 'import json; print(len(json.load(open("eval/targets.json"))), "targets")'
```
Expected: `4 targets`.

- [ ] **Step 3: Commit**

```bash
git add eval/targets.json
git commit -m "feat(eval): define the v1 eval target suite"
```

---

### Task M1.2: Scorer/classifier (TDD)

**Files:**
- Create: `walk/eval/fixtures/stripe-success.action-log.json`
- Create: `walk/eval/test_score.py`
- Create: `walk/eval/score.py`

- [ ] **Step 1: Create the test fixture**

Create `walk/eval/fixtures/stripe-success.action-log.json`:
```json
{
  "goal": "Map payment data",
  "startUrl": "https://docs.stripe.com/get-started",
  "mode": "linear",
  "actions": [
    {"step": 0, "kind": "click", "url": "https://docs.stripe.com/get-started", "title": "Get started | Stripe Documentation"},
    {"step": 1, "kind": "done", "url": "https://docs.stripe.com/get-started/data-migrations/map-payment-data", "title": "Map payment data | Stripe Documentation"}
  ]
}
```

- [ ] **Step 2: Write the failing tests**

Create `walk/eval/test_score.py`:
```python
import os
from score import classify, load_log

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures", "stripe-success.action-log.json")


def test_success_on_matching_final_url():
    log = load_log(FIX)
    target = {"expect_url_contains": "map-payment-data"}
    res = classify(log, target, exit_code=0, wall_seconds=42.0, attempt_log_text="")
    assert res["success"] is True, res
    assert res["steps"] == 2, res
    assert res["final_url"].endswith("map-payment-data"), res
    assert res["category"] == "success", res


def test_no_actions_is_no_actions_category():
    res = classify({"actions": []}, {"expect_url_contains": "x"},
                   exit_code=2, wall_seconds=5.0, attempt_log_text="")
    assert res["success"] is False, res
    assert res["category"] == "no_actions", res


def test_wrong_destination():
    log = load_log(FIX)
    res = classify(log, {"expect_url_contains": "will-not-match"},
                   exit_code=0, wall_seconds=30.0, attempt_log_text="")
    assert res["success"] is False, res
    assert res["category"] == "wrong_destination", res


def test_timeout_category():
    log = load_log(FIX)
    res = classify(log, {"expect_url_contains": "will-not-match"},
                   exit_code=124, wall_seconds=1100.0, attempt_log_text="")
    assert res["category"] == "timeout", res


def test_transient_error_category():
    res = classify({"actions": [{"step": 0, "kind": "click", "url": "https://x", "title": "x"}]},
                   {"expect_url_contains": "nope"},
                   exit_code=1, wall_seconds=12.0,
                   attempt_log_text="fetch failed: 429 Too Many Requests")
    assert res["category"] == "transient_error", res


def test_title_fallback_success():
    log = load_log(FIX)
    res = classify(log, {"expect_title_contains": "Map payment data"},
                   exit_code=0, wall_seconds=20.0, attempt_log_text="")
    assert res["success"] is True, res


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items())
           if k.startswith("test_") and callable(v)]
    for fn in fns:
        fn()
        print(f"ok  {fn.__name__}")
    print(f"ALL {len(fns)} TESTS PASSED")
```

- [ ] **Step 3: Run the tests to verify they FAIL**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk/eval
python3 test_score.py
```
Expected: FAIL — `ModuleNotFoundError: No module named 'score'`.

- [ ] **Step 4: Implement `score.py`**

Create `walk/eval/score.py`:
```python
"""Pure scoring/classification for the Walk eval harness.

Independent success check: did the agent's FINAL action land on the expected
destination (URL/title substring), regardless of the agent's self-reported
judge verdict (which is stubbed to at_destination=true in BEAM=0 / v36)?
"""
import json
import re
import sys

_TRANSIENT = re.compile(r"429|ETIMEDOUT|ECONNRESET|EAI_AGAIN|EPIPE|timed out", re.I)
_RENDER_FAIL = re.compile(r"render failed|ERROR: render", re.I)


def load_log(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {"actions": []}


def classify(log, target, exit_code, wall_seconds, attempt_log_text=""):
    actions = log.get("actions") or []
    steps = len(actions)
    final = actions[-1] if actions else {}
    final_url = (final.get("url") or "")
    final_title = (final.get("title") or "")

    exp_url = (target.get("expect_url_contains") or "").lower()
    exp_title = (target.get("expect_title_contains") or "").lower()

    url_ok = bool(exp_url) and exp_url in final_url.lower()
    title_ok = bool(exp_title) and exp_title in final_title.lower()
    success = (url_ok or title_ok) if (exp_url or exp_title) else False

    if success:
        category = "success"
    elif steps == 0:
        category = "no_actions"
    elif exit_code == 124:
        category = "timeout"
    elif _TRANSIENT.search(attempt_log_text):
        category = "transient_error"
    elif _RENDER_FAIL.search(attempt_log_text):
        category = "render_fail"
    else:
        category = "wrong_destination"

    return {
        "success": success,
        "steps": steps,
        "final_url": final_url,
        "final_title": final_title,
        "category": category,
        "exit_code": exit_code,
        "wall_seconds": wall_seconds,
    }


if __name__ == "__main__":
    # usage: score.py <action_log> <target_json> <exit_code> <wall_seconds> [attempt_log]
    log = load_log(sys.argv[1])
    target = json.loads(sys.argv[2])
    exit_code = int(sys.argv[3])
    wall_seconds = float(sys.argv[4])
    text = ""
    if len(sys.argv) > 5:
        try:
            text = open(sys.argv[5], errors="ignore").read()
        except OSError:
            pass
    print(json.dumps(classify(log, target, exit_code, wall_seconds, text)))
```

- [ ] **Step 5: Run the tests to verify they PASS**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk/eval
python3 test_score.py
```
Expected: `ok  test_...` for each, then `ALL 6 TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/Projects/Hackathons/walk
git add eval/score.py eval/test_score.py eval/fixtures/stripe-success.action-log.json
git commit -m "feat(eval): testable scorer with independent URL/title success check"
```

---

### Task M1.3: Add `SKIP_RENDER` to `make-explainer.sh`

**Files:**
- Modify: `walk/explainer-agent/make-explainer.sh` (the render block, currently lines 103-114)

- [ ] **Step 1: Replace the render block with a guarded version**

In `walk/explainer-agent/make-explainer.sh`, replace this exact block:
```bash
echo
echo "[3/4] Rendering Remotion composition..."
cd "$HERE/remotion"
./node_modules/.bin/remotion render src/index.ts Explainer "$OUT_MP4" --concurrency=8 --log=error 2>&1 | tail -3

if [ ! -f "$OUT_MP4" ]; then
  echo "  ERROR: render failed."
  exit 1
fi

SIZE=$(ls -la "$OUT_MP4" | awk '{print $5}')
echo "  rendered: $OUT_MP4 ($SIZE bytes)"
```
with:
```bash
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
```

- [ ] **Step 2: Verify the script still parses**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk
bash -n explainer-agent/make-explainer.sh && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 3: Commit**

```bash
git add explainer-agent/make-explainer.sh
git commit -m "feat(eval): SKIP_RENDER flag to run navigation without rendering video"
```

---

### Task M1.4: Report aggregator

**Files:**
- Create: `walk/eval/report.py`

- [ ] **Step 1: Implement `report.py`**

Create `walk/eval/report.py`:
```python
"""Aggregate per-attempt *.result.json files into a suite report."""
import glob
import json
import os
import sys
from collections import defaultdict


def build_report(result_dir, label):
    rows = []
    for f in sorted(glob.glob(os.path.join(result_dir, "*.result.json"))):
        with open(f) as fh:
            rows.append(json.load(fh))

    by_target = defaultdict(list)
    for r in rows:
        by_target[r.get("target", "?")].append(r)

    targets = {}
    for tid, rs in by_target.items():
        n = len(rs)
        succ = sum(1 for r in rs if r.get("success"))
        steps = [r["steps"] for r in rs if r.get("steps") is not None]
        walls = [r["wall_seconds"] for r in rs if r.get("wall_seconds") is not None]
        cats = defaultdict(int)
        for r in rs:
            cats[r.get("category", "other")] += 1
        targets[tid] = {
            "n": n,
            "successes": succ,
            "success_rate": round(succ / n, 3) if n else 0,
            "avg_steps": round(sum(steps) / len(steps), 2) if steps else 0,
            "avg_wall_seconds": round(sum(walls) / len(walls), 1) if walls else 0,
            "categories": dict(cats),
        }

    n_all = len(rows)
    succ_all = sum(1 for r in rows if r.get("success"))
    return {
        "label": label,
        "n_total": n_all,
        "success_rate": round(succ_all / n_all, 3) if n_all else 0,
        "avg_steps": round(sum(r["steps"] for r in rows) / n_all, 2) if n_all else 0,
        "avg_wall_seconds": round(sum(r["wall_seconds"] for r in rows) / n_all, 1) if n_all else 0,
        "targets": targets,
    }


if __name__ == "__main__":
    result_dir = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else "run"
    print(json.dumps(build_report(result_dir, label), indent=2))
```

- [ ] **Step 2: Smoke-test the aggregator against a synthetic result dir**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk/eval
mkdir -p /tmp/eval-smoke
echo '{"target":"t1","attempt":1,"success":true,"steps":3,"wall_seconds":40,"category":"success"}' > /tmp/eval-smoke/t1-1.result.json
echo '{"target":"t1","attempt":2,"success":false,"steps":5,"wall_seconds":60,"category":"wrong_destination"}' > /tmp/eval-smoke/t1-2.result.json
python3 report.py /tmp/eval-smoke smoke
```
Expected: JSON with `"success_rate": 0.5`, `"avg_steps": 4.0`, and `targets.t1.categories` showing `success: 1, wrong_destination: 1`.

- [ ] **Step 3: Commit**

```bash
cd ~/Desktop/Projects/Hackathons/walk
git add eval/report.py
git commit -m "feat(eval): suite report aggregator"
```

---

### Task M1.5: Suite orchestrator

**Files:**
- Create: `walk/eval/run-suite.sh`

- [ ] **Step 1: Implement `run-suite.sh`**

Create `walk/eval/run-suite.sh`:
```bash
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
```

- [ ] **Step 2: Make it executable and check syntax**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk
chmod +x eval/run-suite.sh
bash -n eval/run-suite.sh && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 3: Commit**

```bash
git add eval/run-suite.sh
git commit -m "feat(eval): suite orchestrator (loop targets, time, score, aggregate)"
```

---

### Task M1.6: Single-target smoke run (end-to-end wiring check)

**Files:** none (produces output under `eval/results/`, which is gitignored).

> This actually runs the live agent against ONE target via the NemoClaw sandbox. Prereqs: Docker running, the `promo-agent` sandbox up (`~/.local/bin/nemoclaw promo-agent recover` if needed — NEVER `rebuild`/`destroy`), and `NVIDIA_API_KEY` in the env (`source ~/.zshrc`). One attempt, ~1-3 min.

- [ ] **Step 1: Run one attempt against the verified Stripe target**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk
source ~/.zshrc 2>/dev/null
printf '[%s]\n' "$(python3 -c 'import json;print(json.dumps(json.load(open("eval/targets.json"))[0]))')" > /tmp/one-target.json
N=1 ATTEMPT_TIMEOUT=600 ./eval/run-suite.sh smoke 1 /tmp/one-target.json
```
Expected: a `[suite]` line per phase, one `result.json` printed with `final_url`, and a REPORT block with `n_total: 1`. The run should reach `success: true` with `final_url` ending `map-payment-data` (if not, read `final_url` and recalibrate `expect_url_contains` in `targets.json`).

- [ ] **Step 2: Confirm artifacts landed**

Run:
```bash
ls -1 eval/results/smoke-*/ | head
```
Expected: `stripe-map-payment-data-1.log`, `…-1.action-log.json`, `…-1.result.json`, `report.json`.

- [ ] **Step 3: (If the smoke run revealed mis-calibrated expectations) fix targets.json and commit**

Only if needed:
```bash
# edit eval/targets.json expectations to match observed final_url
git add eval/targets.json
git commit -m "fix(eval): calibrate target expectations from smoke run"
```

---

### Task M1.7: Full baseline run (Super) + record results

**Files:**
- Create: `walk/eval/results/baseline-super-<stamp>/report.json` (gitignored output)
- Create: `walk/docs/superpowers/eval-baselines/2026-06-07-baseline-super.md` (committed summary)

> Full suite × N attempts. With 4 targets × N=3 and render skipped, budget ~30-50 min and some NIM token cost. Ensure the sandbox is healthy first.

- [ ] **Step 1: Run the full baseline**

Run:
```bash
cd ~/Desktop/Projects/Hackathons/walk
source ~/.zshrc 2>/dev/null
./eval/run-suite.sh baseline-super 3
```
Expected: a REPORT block with per-target `success_rate`, `avg_steps`, `avg_wall_seconds`, and category breakdowns.

- [ ] **Step 2: Save a committed human-readable baseline summary**

Create `walk/docs/superpowers/eval-baselines/2026-06-07-baseline-super.md` and paste in the printed report JSON plus a one-paragraph read (which targets pass reliably, where the failures cluster by category, and the slowest targets by `avg_wall_seconds`). Then:
```bash
mkdir -p docs/superpowers/eval-baselines
# (create the .md, paste report.json + notes)
git add docs/superpowers/eval-baselines/2026-06-07-baseline-super.md
git commit -m "docs(eval): record Super baseline (success rate, steps, wall-clock, failure categories)"
git push
```

- [ ] **Step 3: Confirm the baseline is the reference for later milestones**

The committed `2026-06-07-baseline-super.md` is the number M2 (hardening) and M3 (Ultra A/B) must beat. M1 is complete when this file exists with real numbers.

---

## Self-Review

**Spec coverage (against `2026-06-07-walk-v1-hardening-design.md`):**
- §5 Repo & lineage → M0.1 (tag/freeze), M0.2 (mirror to private `walk`), M0.3 (name + prune). ✔
- §9 Eval harness + independent success assertion → M1.1–M1.5; independent URL/title check in `score.py`. ✔
- §9 Baseline (Super) → M1.7. ✔
- §11 Testing (unit tests on pure pieces + harness as integration) → M1.2 unit tests; M1.6 smoke = integration. ✔
- Deferred by design (own later plans): §6 canonicalize agent versions, §7 reliability (sandbox image, LaunchAgent, error handling), §8 speed pass, §10 security fix + key rotation, §3/§6 model-as-config-flag plumbing (M3). Explicitly out of this plan's scope per the header. ✔

**Placeholder scan:** No "TBD/TODO/handle edge cases" steps; every code step ships complete code; the two "calibration" notes describe a real post-run tuning action (reading `final_url`), not deferred work.

**Type/name consistency:** `classify(log, target, exit_code, wall_seconds, attempt_log_text)` signature is identical across `score.py`, `test_score.py`, and the `run-suite.sh` CLI call. Result keys (`success`, `steps`, `final_url`, `category`, `wall_seconds`) are produced by `score.py` and consumed unchanged by `report.py`. `targets.json` keys (`id`, `url`, `goal`, `max_steps`, `expect_url_contains`, `expect_title_contains`) match what `run-suite.sh` reads and `score.py` expects. ✔
