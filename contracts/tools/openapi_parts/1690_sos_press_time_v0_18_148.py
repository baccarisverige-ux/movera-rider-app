# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.148 (SOS by press time, Rules
# LAUNCH-RULE.md "Queued (after freeze)" item 1, plan/NUMBERS.md; safety): an SOS after the trip ended is judged by its
# press time `at` (contract.json#sosPressTime). Additive: one optional Incident field and two 409 reasons (a fast phone clock is clamped, never refused).
_SP148 = C["sosPressTime"]
_INC = S["Incident"]
assert "pressedAt" not in _INC["properties"], "Incident.pressedAt exists before v0.18.148"
_INC["properties"]["pressedAt"] = {"allOf": [ref("Timestamp")], "description": "v0.18.148 (sosPressTime.incident): " + _SP148["incident"]}
_SR = S["SosRequest"]
_SR["properties"]["at"]["description"] = _SR["properties"]["at"]["description"] + " v0.18.148 (sosPressTime.at): " + _SP148["at"]
_T148 = (" v0.18.148 (sosPressTime): " + _SP148["liveTrip"] + " " + _SP148["clock"] + " " + _SP148["endedTrip"] + " Refusals: " + " ".join(_SP148["refusals"][k] for k in ("sos_too_old", "sos_not_during_trip", "unchanged"))
         + " " + _SP148["idempotency"])
for _p148 in ("/rider/trips/{tripId}/sos", "/driver/trips/{tripId}/sos"):
    PATHS[_p148]["post"]["description"] += _T148
