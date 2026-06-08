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
