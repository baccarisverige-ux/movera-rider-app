# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.108 (job C9b; owner 2026-11-02,
# Rules decisions/driver-g7.md:84 "At the pickup AND at stops"): auto arrival and the waiting clock at middle stops
# (contract.json#autoArrive.stops, #stopWaits). Additive fields only.
_AS = C["autoArrive"]["stops"]
_V = "v0.18.108: "
_SV = S["StopVisit"]["properties"]
for _k in ("arrivedBy", "away", "pausedSeconds", "pauseCount"):
    assert _k not in _SV, "StopVisit." + _k + " exists before v0.18.108"
_PJ = _AS["projection"]
_SV["arrivedBy"] = {"type": "string", "enum": ["auto", "tap"], "description": _V + _PJ["stops[i].arrivedBy"] + " " + _AS["auto"]}
_SV["away"] = obj({"since": ref("Timestamp")}, ["since"], _V + _PJ["stops[i].away"] + " " + _AS["away"] + " " + _AS["back"] + " " + _AS["money"], addl=False)
_SV["pausedSeconds"] = {"type": "integer", "minimum": 0, "description": _V + _PJ["stops[i].pausedSeconds"]}
_SV["pauseCount"] = {"type": "integer", "minimum": 0, "description": _V + _PJ["stops[i].pauseCount"]}
S["StopVisit"]["description"] += " " + _V + _PJ["mirror"]
_SC = S["StopCommand"]["properties"]
assert "location" not in _SC, "StopCommand.location exists before v0.18.108"
_SC["location"] = {"allOf": [ref("GeoFix")], "description": _V + "optional, on arrive (the first tap and the back tap; ignored on leave). " + _AS["tap"]}
_OP = PATHS["/driver/trips/{tripId}/stops/{stopIndex}/leave"]["post"]
_OP["description"] += " " + _V + _AS["leave"]
