# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.171 (owner 2026-11-27 "Google
# on key screens"): GET /routes/driving answers a real Google road line (source google | stored | estimate),
# TripEta.legRoute on the rider's location events, DispatchDocument.liveTraffic.roadLines and the daily Google budget
# (contract.json#googleRoadLines).
_GR = C["googleRoadLines"]
_V171 = "v0.18.171 (contract.json#googleRoadLines): "
_O = S["OsrmRouteResponse"]["properties"]
assert "source" not in _O, "OsrmRouteResponse.source exists before v0.18.171"
_O["source"] = s(_V171 + _GR["source"] + " " + _GR["codeRule"], enum=["google", "stored", "estimate"])
_N = PATHS["/routes/driving/{coordinates}"]["get"]
_N["description"] = (_N.get("description", "") + " " + _V171 + " ".join(_GR[k] for k in ("navigation", "offRouteRule", "trust", "calls", "atCap", "spacing"))).strip()
_TE = S["TripEta"]["properties"]
assert "legRoute" not in _TE, "TripEta.legRoute exists before v0.18.171"
_TE["legRoute"] = obj({
    "target": s("pickup or dropoff: the leg this route goes to.", enum=["pickup", "dropoff"]),
    "polyline": s("Google encoded polyline (precision 5).", minLength=1),
}, required=("target", "polyline"), desc=_V171 + _GR["riderEvent"], addl=False)
_RE = S["RealtimeEvent"]
_RE["description"] = _RE["description"] + " " + _V171 + "a rider's location event may carry eta.legRoute (" + _GR["riderEvent"] + ")"
_LTD = S["DispatchDocument"]["properties"]["liveTraffic"]["properties"]
assert "roadLines" not in _LTD, "liveTraffic.roadLines exists before v0.18.171"
_LTD["roadLines"] = obj({
    "on": b(_V171 + "true: GET /routes/driving may ask Google for the driver's road line; default follows liveTraffic.on."),
    "maxCallsPerTrip": i(_V171 + _GR["calls"] + " 1 to 4, default 4.", minimum=1, maximum=4),
}, desc=_V171 + _GR["setting"], addl=False)
assert "/admin/maps/google-budget" not in PATHS, "/admin/maps/google-budget exists before v0.18.171"
S["GoogleRoutesBudget"] = obj(OrderedDict([
    ("dailyLimit", i("All Google Routes calls per day, all countries together (default 2000).", minimum=100, maximum=100000)),
    ("quotesPerDay", i("The part kept for prices (quotes), default 1400.", minimum=0, maximum=100000)),
    ("roadLinesPerDay", i("dailyLimit - quotesPerDay: the part for road lines, default 600.", minimum=0, maximum=100000)),
    ("today", obj(OrderedDict([
        ("day", s("The America/Los_Angeles calendar day (YYYY-MM-DD). " + _GR["dayBoundary"], format="date")),
        ("quotes", i(minimum=0)),
        ("roadLines", i(minimum=0)),
    ]), ["day", "quotes", "roadLines"], addl=False)),
]), ["dailyLimit", "quotesPerDay", "roadLinesPerDay", "today"], _V171 + _GR["dailyBudget"], addl=False)
S["GoogleRoutesBudgetCommand"] = obj(OrderedDict([
    ("dailyLimit", i(minimum=100, maximum=100000)),
    ("quotesPerDay", i("At most dailyLimit.", minimum=0, maximum=100000)),
]), ["dailyLimit", "quotesPerDay"], _V171 + _GR["budgetSetting"], addl=False)
op("get", "/admin/maps/google-budget", "adminGetGoogleRoutesBudget", "The daily Google Routes budget and today's use", ["admin"], "Admin · Config",
   ok=(200, "GoogleRoutesBudget"), permission="settings.read", desc=_V171 + _GR["budgetSetting"] + " " + _GR["budgetAlert"])
op("put", "/admin/maps/google-budget", "adminPutGoogleRoutesBudget", "Change the daily Google Routes budget split", ["admin"], "Admin · Config",
   body="GoogleRoutesBudgetCommand", ok=(200, "GoogleRoutesBudget"), mutation=True, permission="settings.publish",
   desc=_V171 + _GR["budgetSetting"] + " " + _GR["dailyBudget"])
