# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.92 (GM 2026-11-14 on the owner
# rule 2026-11-13 23:42 UTC "Movera commission is how much movera keep"): the lost-driver payment on the admin view of
# every trip, paid or not (contract.json#moneyBase.lostDriverPaid.tripField). Additive field only.
_LD = C["moneyBase"]["lostDriverPaid"]
assert "lostDriverPaid" not in S["TripProjection"]["properties"], "TripProjection.lostDriverPaid exists before v0.18.92"
S["TripProjection"]["properties"]["lostDriverPaid"] = {"allOf": [ref("Money")], "description": "v0.18.92: " + _LD["tripField"] + " " + _LD["unpaid"]}
_K = S["TripProjection"]["properties"]["moveraKeepsNow"]
_K["description"] = _K["description"] + " " + C["moneyBase"]["commissionRow"]["fieldAdmin0_18_92"]
