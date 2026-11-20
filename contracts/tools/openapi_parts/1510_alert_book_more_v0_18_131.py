# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.131 (S7 alert-cap MF3, Rules
# plan/NUMBERS.md; Rule A safety): open non-safety alerts are bounded (liveList.openOtherCap) and AlertBookState gets
# the optional alertsMore marker (liveList.more). Additive: one optional field.
_LL131 = C["alertDesk"]["serverDetection"]["liveList"]
_ABS = S["AlertBookState"]
assert "alertsMore" not in _ABS["properties"], "AlertBookState.alertsMore exists before v0.18.131"
_ABS["properties"]["alertsMore"] = {
    "type": "object",
    "description": "v0.18.131 (alertDesk.serverDetection.liveList.more): " + _LL131["more"],
    "required": ["open", "solved"],
    "additionalProperties": False,
    "properties": {"open": {"type": "boolean"}, "solved": {"type": "boolean"}},
}
_T131 = " v0.18.131 (alertDesk.serverDetection.liveList): " + _LL131["open"] + " " + _LL131["more"]
_ABS["description"] += _T131
PATHS["/admin/alerts/book"]["get"]["description"] += _T131
