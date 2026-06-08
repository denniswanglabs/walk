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
