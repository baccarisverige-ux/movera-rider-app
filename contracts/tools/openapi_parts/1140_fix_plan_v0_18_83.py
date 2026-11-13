# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.83 (G34 fix plan; owner 2026-11-13
# 12:18-12:24 UTC): seven repeat phone checks may be shed (GET /rider/trips/active never), admin list total only when the
# list page asks (total=false), GET /admin/trips scheduledBefore (contract.json#fastDispatch.shedPolls,
# #adminListFilters.total.onlyWhenAsked, #adminListFilters.scheduledBefore). The late-timer alarm, the Home backoff and the
# stream rule are text only (no API shape change).
_SP = C["fastDispatch"]["shedPolls"]
for _route in _SP["routes"]:
    _op = PATHS[_route.split(" ", 1)[1]]["get"]
    assert _op["responses"]["503"] == rref("Unavailable"), _route + " 503 changed before v0.18.83"
    _op["description"] = (_op.get("description", "") + " v0.18.83 (S2, owner 'Yes, 7 checks'): under overload it may answer 503 unavailable, "
                          "reason server_busy, Retry-After 2 at once; the app keeps the last value (contract.json#fastDispatch.shedPolls).").strip()
_op = PATHS["/rider/trips/active"]["get"]
assert "server_busy" not in _op.get("description", ""), "/rider/trips/active mentions server_busy before v0.18.83"
_op["description"] = (_op.get("description", "") + " v0.18.83 (owner): never refused with server_busy by load shedding, also under overload "
                      "(the restore read; contract.json#fastDispatch.shedPolls.neverShed).").strip()
_ALT = C["adminListFilters"]["total"]
for _route in _ALT["lists"]:
    _op = PATHS[_route.split(" ", 1)[1]]["get"]
    assert not any(p.get("name") == "total" for p in _op["parameters"]), _route + " has a total param before v0.18.83"
    _op["parameters"].append(q("total", dflt(b(), True), "v0.18.83 (P4-B): false = do not count (the page leaves total out; the rows are the same). "
                               + _ALT["onlyWhenAsked"]))
_op = PATHS["/admin/trips"]["get"]
assert not any(p.get("name") == "scheduledBefore" for p in _op["parameters"]), "/admin/trips has scheduledBefore before v0.18.83"
_op["parameters"].append(q("scheduledBefore", ref("Timestamp"), "v0.18.83 (A2): kind live always passes; kind scheduled only when scheduledAt is at or before this time. "
                           + C["adminListFilters"]["scheduledBefore"]))
