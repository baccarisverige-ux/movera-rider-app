# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.113 (BQ-S13, owner 2026-11-01
# "Keep call open for 1 hour but not chat", Rules decisions/driver-g9.md:38): TripProjection.callOpenUntil, the end of the
# call window after a completed trip (contract.json#inAppCalls.callOpenUntil). Additive, optional.
_CO = C["inAppCalls"]["callOpenUntil"]
assert "callOpenUntil" not in S["TripProjection"]["properties"], "TripProjection.callOpenUntil exists before v0.18.113"
S["TripProjection"]["properties"]["callOpenUntil"] = s(_CO, format="date-time")
for _p in ("/trips/{tripId}", "/rider/trips"):
    _op = PATHS[_p]["get"]
    assert "callOpenUntil" not in _op.get("description", ""), _p + " v0.18.113 text exists before"
    _op["description"] = _op.get("description", "") + (" v0.18.113 (inAppCalls.callOpenUntil): a completed trip carries"
                                                        " callOpenUntil while its zone's calls are on; the apps read it once"
                                                        " when the finished trip opens and show the call button until then.")
