from rule import Rule, RuleTrace, ReplayInput, PolicyResult
from datetime import datetime, timezone


class SnapshotPolicy:
    MIN_AGE_HOURS = 24

    def __init__(self):
        # 모든 규칙을 동일한 인터페이스로 통일
        self.rules = [
            Rule("completed", self.rule_completed),
            Rule("min_age", self.rule_min_age),
            Rule("expire_check", self.rule_expire_check),
        ]

    def replay(self, input: ReplayInput):
        should_delete, decision_reason, expire_date, trace = self.evaluate(
            input.snap,
            input.retain_until,
            input.now
        )

        return {
            "should_delete": should_delete,
            "decision_reason": decision_reason,
            "expire_date": expire_date.isoformat() if expire_date else None,
            "trace": self.serialize_trace(trace),
            "replayed_at": datetime.now(timezone.utc).isoformat()
        }

    @staticmethod
    def serialize_trace(trace: list[RuleTrace]):
        return [
            {
                "rule": t.rule,
                "result": t.result,
                "reason": t.reason,
                "metadata": t.metadata,
            }
            for t in trace
        ]

    def evaluate(
        self,
        snap: dict,
        retain_until: str | None,
        now: datetime | None = None
    ) -> PolicyResult:
        """
        return:
        (
            should_delete,
            decision_reason,
            expire_date,
            trace
        )
        """

        trace: list[RuleTrace] = []

        if now is None:
            now = datetime.now(timezone.utc)

        expire_date = self.extract_expire_date(retain_until)

        # -----------------------------------
        # RetainUntil validation
        # -----------------------------------

        if expire_date is None:
            trace.append(
                RuleTrace(
                    rule="expire_date",
                    result="fail",
                    reason="invalid retain_until"
                )
            )

            return PolicyResult(
                should_delete=False,
                reason="expire_date",
                expire_date=None,
                trace=trace
            )

        trace.append(
            RuleTrace(
                rule="expire_date",
                result="pass",
                metadata={
                    "expire_date": expire_date.isoformat()
                }
            )
        )

        context = {
            "snap": snap,
            "expire_date": expire_date,
            "now": now
        }

        # -----------------------------------
        # Rule execution
        # -----------------------------------

        for rule in self.rules:
            ok, reason, metadata = rule.handler(context)

            trace.append(
                RuleTrace(
                    rule=rule.name,
                    result="pass" if ok else "fail",
                    reason=reason,
                    metadata=metadata
                )
            )
            if not ok:
                return PolicyResult(
                    should_delete=False,
                    reason=rule.name,
                    expire_date=expire_date,
                    trace=trace
                )

        return PolicyResult(
            should_delete=True,
            reason="expired",
            expire_date=expire_date,
            trace=trace 
        )

    # -----------------------------------
    # Rules
    # -----------------------------------

    def rule_completed(self, ctx: dict):
        snap = ctx["snap"]

        state = snap.get("State")

        if state != "completed":
            return (
                False,
                f"state={state}",
                {"state": state}
            )

        return (
            True,
            "",
            {"state": state}
        )

    def rule_expire_check(self, ctx: dict):
        expire_date = ctx["expire_date"]
        now = ctx["now"]
        if expire_date.tzinfo is None:
            expire_date = expire_date.replace(tzinfo=timezone.utc)
        if expire_date > now:
            days_remaining = (expire_date - now).days
            return (
                False,
                f"not expired (expires in {days_remaining}d)",
                {"expire_date": expire_date.isoformat(), "days_remaining": days_remaining}
            )
        return (True, "", {"expire_date": expire_date.isoformat()})

    def rule_min_age(self, ctx: dict):
        snap = ctx["snap"]

        start_time = snap.get("StartTime")

        if not isinstance(start_time, datetime):
            return (
                False,
                "invalid StartTime",
                {}
            )

        # normalize timezone
        if start_time.tzinfo is None:
            start_time = start_time.replace(tzinfo=timezone.utc)
        
        age_hours = (
            ctx["now"] - start_time
        ).total_seconds() / 3600

        metadata = {
            "age_hours": round(age_hours, 2),
            "min_required_hours": self.MIN_AGE_HOURS
        }

        if age_hours < self.MIN_AGE_HOURS:
            return (
                False,
                f"too young ({age_hours:.1f}h)",
                metadata
            )

        return (
            True,
            "",
            metadata
        )

    # -----------------------------------
    # Helpers
    # -----------------------------------

    def extract_expire_date(self, retain_until: str | None):
        if not retain_until:
            return None

        try:
            return datetime.strptime(retain_until, "%Y-%m-%d")

        except ValueError:
            return None