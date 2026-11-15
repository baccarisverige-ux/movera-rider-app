# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.99 (BQ-M25b; M25 supervisor F1,
# Rules audits/impact/m25-card-cash-supervisor.md): on a trip not paid in the car the cash numbers are 0
# (contract.json#priceDisplay.nonCashZero). Wording only; no shape change.
_NZ = C["priceDisplay"]["nonCashZero"]
_V = "v0.18.99: "
_CP = S["CompletePreview"]["properties"]
assert "v0.18.99" not in _CP["cashDue"]["description"], "CompletePreview.cashDue v0.18.99 text exists before"
_CP["cashDue"]["description"] += " " + _V + _NZ["rule"]
_TF = S["TripFinish"]["properties"]["cashToCollect"]
_TF["description"] += " " + _V + _NZ["rule"]
_TP = S["TripProjection"]["properties"]["cashToCollect"]
_TP["description"] += " " + _V + _NZ["rule"]
_CC = S["CompleteCommand"]["allOf"][1]["properties"]["cashCollected"]
_CC["description"] = _CC.get("description", "") + " " + _V + _NZ["complete"]
_OP = PATHS["/driver/trips/{tripId}/complete-preview"]["get"]
_OP["description"] = _OP.get("description", "") + " " + _V + _NZ["rule"]
