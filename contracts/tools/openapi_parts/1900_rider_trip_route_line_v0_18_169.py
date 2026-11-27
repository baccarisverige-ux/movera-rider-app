# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.169 (owner 2026-11-27 "App rider
# blocked here", "Oui, corriger": the rider's trip view keeps the route line after a reopen; Finding leaves on any status
# past searching): TripProjection.routePolyline, the trip's stored Google polyline, rider only (contract.json#riderTripRouteLine).
_RTL = C["riderTripRouteLine"]
_V169 = "v0.18.169 (contract.json#riderTripRouteLine): "
_T169 = S["TripProjection"]["properties"]
assert "routePolyline" not in _T169, "TripProjection.routePolyline exists before v0.18.169"
_T169["routePolyline"] = s(_V169 + _RTL["trip"] + " " + _RTL["calls"] + " " + _RTL["rider"] + " " + _RTL["findingExit"], minLength=1)
