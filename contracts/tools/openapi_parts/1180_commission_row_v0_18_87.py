# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.87 (BQ-M19; owner 2026-11-13
# 23:42 UTC "Movera commission is how much movera keep", GM 2026-11-14: the screen rule): what Movera keeps NOW on a paid
# trip, for the driver view, which has no moneySplit (contract.json#moneyBase.commissionRow). Additive field only.
_CR = C["moneyBase"]["commissionRow"]
assert "moveraKeepsNow" not in S["TripProjection"]["properties"], "TripProjection.moveraKeepsNow exists before v0.18.87"
S["TripProjection"]["properties"]["moveraKeepsNow"] = {"allOf": [ref("Money")], "description": "v0.18.87: " + _CR["field"] + " " + _CR["number"] + " " + _CR["driver"]}
