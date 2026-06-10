import json, sys, os

src = "/tmp/sandbox-action-log.json"
dst = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "remotion", "public", "action-log.json",
)

d = json.load(open(src))
for a in d["actions"]:
    for k in ("screenshotBefore", "screenshotAfter", "screenshot", "screenshotFullPage"):
        if k in a and a[k]:
            a[k] = "screenshots-sandbox/" + a[k].split("/")[-1]

# v3 agent already appends a synthetic done step when the judge says
# at_destination, OR when MAX_STEPS is hit. Only append one if the last
# action is still a click/scroll (defensive — shouldn't happen in v3).
if d["actions"] and d["actions"][-1]["kind"] in ("click", "scroll"):
    last = d["actions"][-1]
    d["actions"].append({
        "step": last["step"] + 1,
        "kind": "done",
        "url": last["url"],
        "title": last.get("title", ""),
        "screenshot": last["screenshotAfter"],
        "reasoning": "synthetic done — reached goal page",
    })

json.dump(d, open(dst, "w"), indent=2)
print(f"actions: {len(d['actions'])}")
for a in d["actions"]:
    if a["kind"] == "click":
        tgt = a.get("target", {}).get("text", "?")
        ck = a.get("changeKind", "?")
        print(f"  CLICK '{tgt[:30]}' [{ck}] -> url ends {a['url'][-40:]}")
    elif a["kind"] == "scroll":
        dirn = a.get("direction", "?")
        px = a.get("pixels", "?")
        print(f"  SCROLL {dirn} {px}px ({a.get('scrollYBefore', '?')} -> {a.get('scrollYAfter', '?')})")
    else:
        print(f"  {a['kind'].upper()}  ({a.get('reasoning', '')[:50]})")
