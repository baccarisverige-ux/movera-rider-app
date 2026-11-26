# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.167 (owner 2026-11-26 "Oui, corriger":
# the rider map draws the real Google route): Quote.routePolyline, the stored Google polyline, only when routeSource is google
# (contract.json#googleRouteLine).
_GRL = C["googleRouteLine"]
_V167 = "v0.18.167 (contract.json#googleRouteLine): "
_Q167 = S["Quote"]["properties"]
assert "routePolyline" not in _Q167, "Quote.routePolyline exists before v0.18.167"
_Q167["routePolyline"] = s(_V167 + _GRL["quote"] + " " + _GRL["calls"] + " " + _GRL["rider"], minLength=1)
