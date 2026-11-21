# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.127 (S7 W2 Q119, plan 0.21; owner
# 2026-11-15 "All except GPS (Rec.)", server only; Rules decisions/session-2026-11-06.md:1381): wording only, no shape
# change. RiderTripEvent is not sent for a GPS update (trip event kind location); the text comes from
# contract.json#bookedRideSeen.riderTripEvent.
_RTE = S["RiderTripEvent"]
assert "v0.18.127" not in _RTE.get("description", ""), "RiderTripEvent v0.18.127 text exists before"
_RTE["description"] = (_RTE.get("description", "") + " v0.18.127 (contract.json#bookedRideSeen.riderTripEvent): not sent for a GPS update (trip event kind location: a position fix or an ETA tick); every other event of the rider's trips still sends it.").strip()
