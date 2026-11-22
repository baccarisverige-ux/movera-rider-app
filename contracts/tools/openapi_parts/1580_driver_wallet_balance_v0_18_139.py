# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.139 (driver wallet D5; owner
# button 2026-11-20 "Yes, server + app (Rec.)", Rules audits/impact/driver-wallet-cash.md): GET /driver/earnings carries
# the driver's balance with Movera now, the server's own sum (contract.json#driverWalletBalance). Additive: one
# optional field.
_DWB = C["driverWalletBalance"]
_V139 = "v0.18.139 (driverWalletBalance): "
_ER139 = S["EarningsReport"]
assert "moveraBalance" not in _ER139["properties"], "EarningsReport.moveraBalance exists before v0.18.139"
_ER139["properties"]["moveraBalance"] = {
    "type": "object",
    "description": _V139 + _DWB["field"] + " " + _DWB["sum"],
    "required": ["owedToMovera", "moveraOwesYou"],
    "additionalProperties": False,
    "properties": {
        "owedToMovera": {"allOf": [ref("Money")], "description": _V139 + "what the driver owes Movera now (= debtModel.driverOwes.owed of the report's currency); 0 when nothing."},
        "moveraOwesYou": {"allOf": [ref("Money")], "description": _V139 + "what Movera owes the driver now (his next payout worked out now, less the carried rest); 0 when nothing."},
    },
}
PATHS["/driver/earnings"]["get"]["description"] = (PATHS["/driver/earnings"]["get"].get("description", "") + " " + _V139 + _DWB["field"] + " " + _DWB["driver"]).strip()

# v0.18.139, second part (owner 2026-11-20 "ask driver monthly to pay how much due to Movera ... link to pay", "Link sumup
# for exp"): the TEMPORARY monthly pay request (contract.json#driverPayRequest). Setting on the country standard (off),
# the driver's read route, the notice kind; confirmation stays the admin's "Driver paid Movera".
_DPR = C["driverPayRequest"]
_V139P = "v0.18.139 (driverPayRequest): "
_cr139 = S["CountryRules"]["properties"]
assert "driverPayRequest" not in _cr139, "CountryRules.driverPayRequest exists before v0.18.139"
S["DriverPayRequestSetting"] = obj({
    "enabled": dflt(b("Off by default in every country: nothing is asked until the admin switches it on."), False),
    "dayOfMonth": dflt(i("The day of the month the drivers are asked (from 09:00 in the country's time zone).", minimum=1, maximum=28), 1),
    "payLink": dflt(s("Legacy, hidden while Stripe pays (v0.18.141 DRAFT): the payment link the Pay Movera button opens (https only; '' = none); not needed to switch on.", maxLength=500, pattern="^(https://[^\\s]+)?$"), ""),
    "minAmount": {"oneOf": [ref("Money"), {"type": "null"}], "description": "Only a driver who owes MORE than this is asked. The country's currency, 0 or above; required when enabled."}},
    ["enabled"], _V139P + _DPR["setting"], addl=False)
_cr139["driverPayRequest"] = ref("DriverPayRequestSetting")
S["DriverPayMovera"] = obj({
    "enabled": b("The country's monthly pay request is on."),
    "owedToMovera": {"allOf": [ref("Money")], "description": "What the driver owes Movera now (= debtModel.driverOwes.owed); 0 when nothing."},
    "reference": s("'<driverId>-<YYYYMM>': the text he writes on the payment.", maxLength=80),
    "payLink": s("Only while enabled and set: opened as it is (no amount added).", maxLength=500),
    "minAmount": ref("Money"),
    "request": obj({"month": s(pattern="^\\d{4}-\\d{2}$"), "askedAt": ref("Timestamp"), "askedAmount": ref("Money")}, ["month", "askedAt", "askedAmount"], "His newest monthly request, if any.", addl=False)},
    ["enabled", "owedToMovera", "reference"], _V139P + _DPR["read"], addl=False)
op("get", "/driver/pay-movera", "getDriverPayMovera", "What the driver owes Movera and where to pay (monthly pay request)", ["driver"], "Driver · Account",
   ok=(200, "DriverPayMovera"), read_only=True, desc=_V139P + _DPR["read"] + " " + _DPR["driver"] + " " + _DPR["confirm"])
PATHS["/admin/drivers/{driverId}/paid-movera"]["post"]["description"] += " " + _V139P + _DPR["confirm"]
PATHS["/admin/config/{doc}"]["put"]["description"] += " " + _V139P + _DPR["setting"]
PATHS["/admin/config/{doc}/restore"]["post"]["description"] += " " + _V139P + "Restore keeps driverPayRequest (pricingHistory.restoreKeeps)."
_rk139 = S["ConfigDraftUpdate"]["properties"]["removeKeys"]
assert "driverPayRequest" in C["configDocs"]["keptKeys"]["country_rules"], "driverPayRequest is a kept key"
_rk139["items"]["enum"] = sorted(set(_rk139["items"]["enum"]) | {"driverPayRequest"})
_rk139["maxItems"] = len(_rk139["items"]["enum"])
