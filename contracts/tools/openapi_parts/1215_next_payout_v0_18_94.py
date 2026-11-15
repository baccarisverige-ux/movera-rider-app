# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.94 (job A5 / BQ-M13; owner G10-2
# "Admin sets day and time (Recommended)" ... "driver app shows next payout", Rules decisions/driver-g10.md:6): GET
# /driver/payouts tells the driver when his next payout is made (contract.json#payouts.schedule.nextPayout). Additive only.
_NP = C["payouts"]["schedule"]["nextPayout"]
_V = "v0.18.94: "
assert "DriverPayoutPage" not in S, "DriverPayoutPage exists before v0.18.94"
S["DriverPayoutPage"] = {"allOf": [ref("PayoutPage"), {"type": "object", "properties": {
    "nextPayoutAt": {"allOf": [ref("Timestamp")], "description": _V + _NP["rule"]},
    "nextPayoutLocal": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}$", "description": _V + "nextPayoutAt as wall-clock time in nextPayoutTimeZone. " + _NP["display"]},
    "nextPayoutTimeZone": {"type": "string", "description": _V + "the IANA time zone of the driver's payouts (his first zone, else his country)."}}}],
    "description": _V + "Page<Payout> of GET /driver/payouts with the driver's next payout moment. " + _NP["fields"]}
_R = PATHS["/driver/payouts"]["get"]["responses"]["200"]["content"]["application/json"]
assert _R["schema"] == ref("PayoutPage"), "GET /driver/payouts answers PayoutPage before v0.18.94"
_R["schema"] = ref("DriverPayoutPage")
