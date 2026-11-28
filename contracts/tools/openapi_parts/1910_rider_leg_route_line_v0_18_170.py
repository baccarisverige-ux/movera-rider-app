# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.170 (owner approved "rider
# Waiting/on-trip road line from the stored Google route, 0 extra Google calls"): TripProjection.legRoute, the stored
# Google route of the trip's current leg (trips.eta_route), rider only (contract.json#riderLegRouteLine).
_RLL = C["riderLegRouteLine"]
_V170 = "v0.18.170 (contract.json#riderLegRouteLine): "
_T170 = S["TripProjection"]["properties"]
assert "legRoute" not in _T170, "TripProjection.legRoute exists before v0.18.170"
_T170["legRoute"] = obj({
    "target": s("pickup: driver position to the pickup; dropoff: to the drop-off through the stops still ahead.", enum=["pickup", "dropoff"]),
    "polyline": s("Google encoded polyline (precision 5).", minLength=1),
}, required=("target", "polyline"), desc=_V170 + _RLL["trip"] + " " + _RLL["calls"] + " " + _RLL["rider"], addl=False)
