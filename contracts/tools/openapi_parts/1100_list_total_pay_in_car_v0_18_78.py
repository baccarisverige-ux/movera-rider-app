# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.78 (owner 2026-11-12 ~17:30 item 5
# + G33): admin list pages carry an optional total; GET /admin/incidents takes driverId / riderId; the rider's pay-in-car
# line is wording only (contract.json#finish.payInCarLine, #adminListFilters.total, #adminListFilters.incidentsByPerson).
_ALT = C["adminListFilters"]["total"]
_TOTAL = i("v0.18.78 (owner item 5): only on " + ", ".join(_ALT["lists"]) + ". " + _ALT["rule"], minimum=0)
for _route in _ALT["lists"]:
    _op = PATHS[_route.split(" ", 1)[1]]["get"]
    _page = _op["responses"]["200"]["content"]["application/json"]["schema"]["$ref"].split("/")[-1]
    _extra = S[_page]["allOf"][1]["properties"]
    assert "total" not in _extra, _page + " has total before v0.18.78"
    _extra["total"] = _TOTAL
    _op["description"] = (_op.get("description", "") + " v0.18.78: the page carries total (" + _ALT["note"] + " contract.json#adminListFilters.total).").strip()
_op = PATHS["/admin/incidents"]["get"]
assert not any(p.get("name") in ("driverId", "riderId") for p in _op["parameters"]), "/admin/incidents had driverId / riderId before v0.18.78"
_IBP = C["adminListFilters"]["incidentsByPerson"]
_op["parameters"] += [q("driverId", ref("Id"), "v0.18.78: cases whose Incident.driverId is this driver. " + _IBP),
                      q("riderId", ref("Id"), "v0.18.78: cases whose Incident.riderId is this rider. " + _IBP)]
assert S["TripFinish"]["properties"]["cashToCollect"] == ref("Money"), "TripFinish.cashToCollect changed before v0.18.78"
S["TripFinish"]["properties"]["cashToCollect"] = {"allOf": [ref("Money")], "description": "v0.18.78 (G33): " + C["finish"]["payInCarLine"]}
