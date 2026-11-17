# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.117 (S7 notes + alert-cap MF3;
# owner Sitting W2 Q113 + Q114, Rules decisions/session-2026-11-06.md; Rules audits/impact/alert-cap-safety-supervisor.md
# MF3 + N2): wording only, no shape change. The limit and order of AlertBookState.alerts
# (contract.json#alertDesk.serverDetection.liveList) and the GPS send rules of POST /driver/location
# (contract.json#driverHome.locationSend), including its Idempotency-Key exception.
_LL = C["alertDesk"]["serverDetection"]["liveList"]
_LS = C["driverHome"]["locationSend"]
_V117 = "v0.18.117 "

# --- the admin alert list
_LLT = (_V117 + "(alertDesk.serverDetection.liveList): AlertBookState.alerts: " + _LL["open"] + " " + _LL["solved"]
        + " " + _LL["order"] + " " + _LL["more"])
_book = PATHS["/admin/alerts/book"]["get"]
assert "liveList" not in _book["description"], "GET /admin/alerts/book v0.18.117 text exists before"
_book["description"] += " " + _LLT
assert "liveList" not in S["AlertBookState"]["description"], "AlertBookState v0.18.117 text exists before"
S["AlertBookState"]["description"] += " " + _LLT

# --- the GPS send
_loc = PATHS["/driver/location"]["post"]
assert "locationSend" not in _loc["description"], "POST /driver/location v0.18.117 text exists before"
_loc["description"] += (" " + _V117 + "(driverHome.locationSend): " + _LS["newFix"] + " " + _LS["rideCheckScan"]
                        + " " + _LS["idempotencyKey"])
# The shared IdempotencyKey parameter says "the same key replays the committed response"; this route is the exception,
# so it gets its own copy of the header with the exception text (same name, same rules for the value).
_ik = [k for k, p in enumerate(_loc["parameters"]) if p.get("$ref", "").endswith("/IdempotencyKey")]
assert len(_ik) == 1, "POST /driver/location takes the shared IdempotencyKey before v0.18.117"
_loc["parameters"][_ik[0]] = dict(PARAMS["IdempotencyKey"], description=_V117 + "(driverHome.locationSend.idempotencyKey): " + _LS["idempotencyKey"])
_loc["x-idempotency"] = "checked, not stored"
