# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.143 (owner 2026-11-20 "must rider
# can change !!!!", Rules plan/NUMBERS.md): while a live trip is searched the rider changes the route, pickup to any place
# (onTrip.routeChange.whileSearching). Additive: optional fields and one transition (change_route).
_WS = C["onTrip"]["routeChange"]["whileSearching"]
_T143 = " v0.18.143 (onTrip.routeChange.whileSearching): " + _WS["note"] + " " + " ".join(_WS["flow"]) + " " + _WS["smallMove"] + " " + _WS["zone"]
S["RouteQuote"]["properties"]["pickup"] = {"allOf": [ref("Place")], "description": "v0.18.143: the new pickup, only on a quote made while searching."}
S["TripRouteChange"]["properties"]["pickup"] = {"allOf": [ref("Place")], "description": "v0.18.143: the new pickup of a change made while searching."}
S["TripRouteChange"]["properties"]["reason"] = s("v0.18.143: rider_changed_route on a change made while searching (no driver had accepted).", enum=["rider_changed_route"])
S["RouteQuoteRequest"]["properties"]["pickup"]["description"] += " v0.18.143: accepted only while searching (any distance); after accept 400 invalid_body."
PATHS["/trips/{tripId}/route-quote"]["post"]["description"] += _T143
PATHS["/trips/{tripId}"]["patch"]["description"] += _T143
