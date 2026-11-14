# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.89 (owner 2026-11-14 "make sure
# rider and driver app show correct prices every where" + "Check all apps"; Rules audits/price-display-2026-11-14/REPORT.md
# contract gaps): the server sends every money number the apps show (contract.json#priceDisplay). Additive fields only.
_PD = C["priceDisplay"]
_V = "v0.18.89: "
for _schema, _field in (("Offer", "driverTotal"), ("Offer", "cashToCollect"), ("TripRouteChange", "driverTotal"),
                        ("TripProjection", "cancelPreview"), ("TripProjection", "cashToCollect"), ("TripFinish", "owedToMovera"),
                        ("Payout", "summary")):
    assert _field not in S[_schema]["properties"], _schema + "." + _field + " exists before v0.18.89"
S["Offer"]["properties"]["driverTotal"] = {"allOf": [ref("Money")], "description": _V + _PD["offer"]["driverTotal"]}
S["Offer"]["properties"]["cashToCollect"] = {"allOf": [ref("Money")], "description": _V + _PD["offer"]["cashToCollect"]}
S["Offer"]["properties"]["pickupPay"] = {"allOf": [ref("Money")], "description": _V + _PD["offer"]["pickupPay"]}
S["TripRouteChange"]["properties"]["driverTotal"] = {"allOf": [ref("Money")], "description": _V + _PD["routeChange"]}
S["TripProjection"]["properties"]["cashToCollect"] = {"allOf": [ref("Money")], "description": _V + _PD["tripCashToCollect"]}
_CP = _PD["cancelPreview"]
S["CancelPreview"] = obj({"feeNow": ref("Money"), "kind": s(enum=["cancel", "no_show"]), "freeUntil": ref("Timestamp"),
                          "feeAfterFree": ref("Money"), "kindAfterFree": s(enum=["cancel", "no_show"])}, ["feeNow", "kind"],
                         _V + _CP["shape"] + " " + _CP["when"] + " " + _CP["rule"] + " " + _CP["apps"], addl=False)
S["TripProjection"]["properties"]["cancelPreview"] = {"allOf": [ref("CancelPreview")], "description": _V + "rider and admin views (contract.json#priceDisplay.cancelPreview)."}
S["TripFinish"]["properties"]["owedToMovera"] = {"allOf": [ref("Money")], "description": _V + _PD["owedToMovera"]}
_PS = _PD["payoutSummary"]
S["PayoutSummary"] = obj({"driverGets": ref("Money"), "moveraGets": ref("Money")},
                         ["driverGets", "moveraGets"],
                         _V + _PS["owner"] + " " + _PS["shape"] + " " + _PS["rule"] + " " + _PS["display"], addl=False)
S["Payout"]["properties"]["summary"] = {"allOf": [ref("PayoutSummary")], "description": _V + "driver and admin views: the 2 lines Driver gets / Movera gets (contract.json#priceDisplay.payoutSummary)."}
_L = S["Payout"]["properties"]["lines"]
assert _L["description"].endswith("The driver app shows only the total."), "Payout.lines text changed before v0.18.89"
_L["description"] = _L["description"][: -len("The driver app shows only the total.")] + (
    "v0.18.89 (owner 2026-11-14 \"no details\"): the payout card in the driver app and the admin shows only the 2 lines of Payout.summary (Driver gets / Movera gets), not these lines.")
