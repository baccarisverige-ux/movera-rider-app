# v0.18.41 §66 (fix plan A14, contract.json#routeVia): POST /routes through the stops (optional via).
# A part of tools/gen_openapi.py (rule 25 split), run in name order with its globals, after 0200 defines the op.
RV = C["routeVia"]
S["RouteRequest"] = obj({"mode": s(enum=MP["routeModes"]), "from": ref("LatLng"), "to": ref("LatLng"),
                         "via": arr(ref("LatLng"), maxItems=10, description="v0.18.41 §66: " + RV["request"])}, ["mode", "from", "to"])
PATHS["/routes"]["post"]["description"] += " v0.18.41 §66: " + RV["fallback"]
