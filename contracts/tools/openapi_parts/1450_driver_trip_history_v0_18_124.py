# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.124 (C10 empty driver history;
# owner G11 Q10 "Load from server (Recommended)", full-audit Q9 "Yes, on the server (Recommended)"; Rules
# decisions/driver-g11.md, audits/impact/findings-g18-g23-2026-11-17.md): GET /driver/trips, the driver's own ended trips
# from the server, paged (contract.json#driverTripHistory). Additive.
_DH = C["driverTripHistory"]
_V124 = "v0.18.124 "
assert "/driver/trips" not in PATHS, "/driver/trips exists before v0.18.124"
assert "DriverTripHistoryItem" not in S, "DriverTripHistoryItem exists before v0.18.124"
S["DriverTripHistoryItem"] = {"allOf": [ref("TripProjection"), obj({
    "earned": {"allOf": [ref("Money")], "description": _V124 + _DH["earned"]},
    "cashCollected": {"allOf": [ref("Money")], "description": _V124 + _DH["cashCollected"]},
    "endedAt": {"allOf": [ref("Timestamp")], "description": _V124 + "When the trip ended (the History day and time); absent when not recorded."},
    "distanceMeters": i(_V124 + "The driven distance in metres, when known.", minimum=0),
}, ["earned"])], "description": _V124 + _DH["item"]}
S["DriverTripHistoryPage"] = obj({"items": arr(ref("DriverTripHistoryItem")), "nextCursor": {"type": ["string", "null"], "description": "Opaque; null on the last page."}},
                                 ["items", "nextCursor"], _V124 + "Page of GET /driver/trips.")
op("get", "/driver/trips", "listDriverTrips", "The driver's own ended trips (ride history)", ["driver"], "Driver · Trip",
   params=[pref("Cursor"), {"name": "limit", "in": "query", "required": False, "schema": i(minimum=1, maximum=50, default=20)},
           q("status", s(enum=_DH["statuses"]), multi=True), pref("From"), pref("To")],
   ok=(200, "DriverTripHistoryPage"),
   desc=_V124 + "(contract.json#driverTripHistory): " + " ".join(_DH[k] for k in ("note", "endpoint", "statusRule", "scale", "clients")))
