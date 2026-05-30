def diff_traces(trace_v1, trace_v2):
    diff = []

    v1 = {get_rule(t): t for t in trace_v1}
    v2 = {get_rule(t): t for t in trace_v2}

    all_rules = set(v1.keys()) | set(v2.keys())

    for rule in all_rules:
        r1 = v1.get(rule)
        r2 = v2.get(rule)

        if not r1:
            diff.append({
                "rule": rule,
                "v1": None,
                "v2": r2.result if r2 else None,
                "type": "added_in_v2"
            })

        elif not r2:
            diff.append({
                "rule": rule,
                "v1": r1.result,
                "v2": None,
                "type": "removed_in_v2"
            })

        elif r1.result != r2.result:
            diff.append({
                "rule": rule,
                "v1": r1.result,
                "v2": r2.result,
                "type": "changed"
            })

    return diff


def find_root_cause(diff):
    for d in diff:
        if d["type"] == "changed":
            return d["rule"]
    return None


def classify_impact(rule, trace_v1, trace_v2):
    r1 = next((t for t in trace_v1 if get_rule(t) == rule), None)
    r2 = next((t for t in trace_v2 if get_rule(t) == rule), None)
    r1_result = get_result(r1) if r1 else None
    r2_result = get_result(r2) if r2 else None

    if r1_result is None:
        return ("MEDIUM", "added")
    if r2_result is None:
        return ("MEDIUM", "removed")
    if r1_result == "pass" and r2_result == "fail":
        return ("HIGH", "stricter")
    if r1_result == "fail" and r2_result == "pass":
        return ("HIGH", "more_lenient")
    return ("LOW", "unchanged")


def build_explanation(diff, trace_v1, trace_v2):
    changed = [d for d in diff if d["type"] in ("changed", "added_in_v2", "removed_in_v2")]

    if not changed:
        return {
            "decision_changed": False,
            "root_cause": None,
            "impact_level": "LOW",
            "direction": None,
            "changed_rules": [],
            "explanation": "No behavioral difference detected",
        }

    level_order = {"HIGH": 2, "MEDIUM": 1, "LOW": 0}
    rule_impacts = []
    for d in changed:
        rule = d["rule"]
        impact_level, direction = classify_impact(rule, trace_v1, trace_v2)
        rule_impacts.append({
            "rule": rule,
            "v1": d.get("v1"),
            "v2": d.get("v2"),
            "impact": impact_level,
            "direction": direction,
        })

    top = max(rule_impacts, key=lambda x: level_order.get(x["impact"], 0))
    return {
        "decision_changed": True,
        "root_cause": top["rule"],
        "impact_level": top["impact"],
        "direction": top["direction"],
        "changed_rules": rule_impacts,
        "explanation": generate_explanation(top["rule"], changed, top["direction"]),
    }


def generate_explanation(rule, changed, direction=None):
    dir_text = f" ({direction})" if direction else ""
    return (
        f"Rule '{rule}'{dir_text} behavior changed in policy v2, "
        f"affecting deletion decisions. {len(changed)} rule(s) differ."
    )


def aggregate_shadow_diffs(records):
    rule_counts = {}
    for record in records:
        for rc in (record.get("explanation") or {}).get("changed_rules", []):
            rule = rc["rule"]
            direction = rc.get("direction", "unknown")
            if rule not in rule_counts:
                rule_counts[rule] = {"stricter": 0, "more_lenient": 0,
                                     "added": 0, "removed": 0, "total": 0}
            rule_counts[rule][direction] = rule_counts[rule].get(direction, 0) + 1
            rule_counts[rule]["total"] += 1
    return {
        "snapshots_with_diff": sum(1 for r in records if r.get("shadow_diff")),
        "rule_diff_counts": rule_counts,
    }


def get_rule(t):
    return getattr(t, "rule", t.get("rule"))


def get_result(t):
    return getattr(t, "result", t.get("result"))
