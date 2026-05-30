from datetime import timezone


def get_tag(resource: dict, key: str) -> str | None:
    for tag in resource.get("Tags", []):
        if tag.get("Key") == key:
            return tag.get("Value")
    return None


def build_record(snap_id, name, instance, retain_until, *, reason, expire_date, now, dry_run):
    days_left = None
    if expire_date is not None:
        exp = expire_date.replace(tzinfo=timezone.utc) if expire_date.tzinfo is None else expire_date
        days_left = (exp - now).days
    return {
        "id": snap_id,
        "name": name,
        "instance": instance,
        "retain_until": retain_until,
        "reason": reason,
        "expire_date": expire_date.isoformat() if expire_date else None,
        "days_left": days_left,
        "dry_run": dry_run,
    }
