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
