# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.146 (audit N5, owner 2026-11-20
# "Must see all kind", Rules plan/NUMBERS.md): EarningsPeriod.rideCounts, every ride of the period by kind
# (contract.json#driverRideCounts). Additive: one optional field.
_RC146 = C["driverRideCounts"]
_EP = S["EarningsPeriod"]
assert "rideCounts" not in _EP["properties"], "EarningsPeriod.rideCounts exists before v0.18.146"
_EP["properties"]["rideCounts"] = {
    "type": "object",
    "description": "v0.18.146 (driverRideCounts): " + _RC146["rule"],
    "required": ["completed", "cancelled", "noShow"],
    "additionalProperties": False,
    "properties": {"completed": i(minimum=0), "cancelled": i(minimum=0), "noShow": i(minimum=0)},
}
_OP146 = PATHS["/driver/earnings"]["get"]
_OP146["description"] = (_OP146["description"] + " " if _OP146.get("description") else "") + "v0.18.146 (driverRideCounts): " + _RC146["field"]
