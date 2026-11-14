# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.93 (job C9; owner 2026-11-02
# review Q3 "Both: auto + button", Rules decisions/driver-g7.md:83-84): the server marks the driver arrived within
# DriverAppConfig.waiting.autoArriveMeters and stops the waiting clock while he is farther than waiting.leaveMeters
# (contract.json#autoArrive). Additive fields only.
_AA = C["autoArrive"]
_V = "v0.18.93: "
_W = S["Waiting"]["properties"]
for _k in ("arrivedBy", "away", "pausedSeconds", "pauseCount"):
    assert _k not in _W, "Waiting." + _k + " exists before v0.18.93"
_P = _AA["projection"]
_W["arrivedBy"] = {"type": "string", "enum": ["auto", "tap"], "description": _V + _P["Waiting.arrivedBy"] + " " + _AA["auto"]}
_W["away"] = obj({"since": ref("Timestamp")}, ["since"], _V + _P["Waiting.away"] + " " + _AA["away"] + " " + _AA["back"] + " " + _AA["money"], addl=False)
_W["pausedSeconds"] = {"type": "integer", "minimum": 0, "description": _V + _P["Waiting.pausedSeconds"]}
_W["pauseCount"] = {"type": "integer", "minimum": 0, "description": _V + _P["Waiting.pauseCount"]}
_T = S["TripTerms"]["properties"]
for _k in ("autoArriveMeters", "leaveMeters"):
    assert _k not in _T, "TripTerms." + _k + " exists before v0.18.93"
_T["autoArriveMeters"] = {"type": "integer", "description": _V + _P["TripTerms.autoArriveMeters"] + " " + _AA["settings"]["kept"]}
_T["leaveMeters"] = {"type": "integer", "description": _V + _P["TripTerms.leaveMeters"]}
_DW = S["DriverWaiting"]["allOf"][-1]["properties"]
_ST = _AA["settings"]
for _k, _key in (("autoArriveMeters", "arriveMeters"), ("leaveMeters", "leaveMeters")):
    assert _k not in _DW, "DriverWaiting." + _k + " exists before v0.18.93"
    _r = _ST[_key]["range"]
    _DW[_k] = {"type": "integer", "minimum": _r[0], "maximum": _r[1], "description": _V + _ST[_key]["where"] + " Default " + str(_ST[_key]["default"]) + ". " + _ST["validation"]}
