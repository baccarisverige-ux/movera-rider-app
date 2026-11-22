# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.136 (DRAFT, Stripe test or live keys;
# owner 2026-11-20 "So we use stripe"): the rider pays an owed fee in the app (contract.json#stripeFees).
_SF = C["stripeFees"]
_V136 = "v0.18.136 (stripeFees): "
_cr136 = S["CountryRules"]["properties"]
assert "riderFeeStripe" not in _cr136, "CountryRules.riderFeeStripe exists before v0.18.136"
S["RiderFeeStripeSetting"] = obj({"enabled": dflt(b("Off by default in every country."), False)}, ["enabled"], _V136 + _SF["setting"], addl=False)
_cr136["riderFeeStripe"] = ref("RiderFeeStripeSetting")
S["StripeFeePayment"] = obj({
    "tripId": s(), "paymentIntentId": s(maxLength=255),
    "amount": {"allOf": [ref("Money")], "description": "The server's amount: min(fee, debt now)."},
    "status": s(enum=["requires_payment", "processing", "succeeded", "failed", "canceled", "refund_pending", "refunded"]),
    "clientSecret": s("Only to the paying rider while requires_payment.", maxLength=500),
    "publishableKey": s("The Stripe publishable key of the server's mode (pk_test_ or pk_live_, stripeFees.keys), with clientSecret.", maxLength=255),
    "createdAt": ref("Timestamp"), "paidAt": ref("Timestamp"), "refundedAt": ref("Timestamp"),
    "paidTwice": b("Succeeded after the fee was already settled another way: refund it."),
    "overpaid": {"allOf": [ref("Money")], "description": "The part that took nothing off a debt: refund it."},
    "amountMismatch": b("A succeeded event with another amount or currency: the fee is unchanged.")},
    ["tripId", "paymentIntentId", "amount", "status", "createdAt"], _V136 + _SF["payment"], addl=False)
S["StripeRefundBody"] = obj({"reason": s(maxLength=300)}, ["reason"], addl=False)
S["Rider"]["properties"]["feesPayableByCard"] = arr(obj({"tripId": s(), "amount": ref("Money")}, ["tripId", "amount"], addl=False), description=_V136 + _SF["profile"])
op("post", "/rider/fees/{tripId}/pay", "payRiderFeeStripe", "Start paying an owed fee with Stripe", ["rider"], "Rider · Payments",
   params=[pref("TripId")], ok=(200, "StripeFeePayment"), mutation=True, desc=_V136 + _SF["pay"] + " " + _SF["rider"])
_wh = op("post", "/webhooks/stripe", "stripeWebhook", "Stripe events (signature checked, no sign-in)", [], "System",
   ok=(200, None), desc=_V136 + _SF["webhook"] + " " + _SF["keys"])
_wh["security"] = []
_wh["x-public"] = True
_wh["parameters"] = [{"name": "Stripe-Signature", "in": "header", "required": True, "schema": {"type": "string", "maxLength": 2000}}]
op("get", "/admin/riders/{riderId}/fee-payments", "adminRiderFeePayments", "A rider's Stripe fee payments", ["admin"], "Admin · People",
   params=[pref("RiderId")], ok=(200, None), read_only=True, desc=_V136 + _SF["adminRead"])
op("post", "/admin/riders/{riderId}/fees/{tripId}/stripe-refund", "adminRefundRiderFeeStripe", "Refund a fee paid with Stripe", ["admin"], "Admin · People",
   params=[pref("RiderId"), pref("TripId")], body="StripeRefundBody", ok=(200, None), mutation=True, desc=_V136 + _SF["refund"])
PATHS["/admin/riders/{riderId}/fees/{tripId}/mark-paid"]["post"]["description"] += " " + _V136 + "Mark as paid by hand stays; a fee paid with Stripe becomes paid by the webhook (stripeFees.webhook)."
PATHS["/admin/config/{doc}"]["put"]["description"] += " " + _V136 + _SF["setting"]
PATHS["/admin/config/{doc}/restore"]["post"]["description"] += " " + _V136 + "Restore keeps riderFeeStripe (pricingHistory.restoreKeeps)."
_rk136 = S["ConfigDraftUpdate"]["properties"]["removeKeys"]
assert "riderFeeStripe" in C["configDocs"]["keptKeys"]["country_rules"], "riderFeeStripe is a kept key"
_rk136["items"]["enum"] = sorted(set(_rk136["items"]["enum"]) | {"riderFeeStripe"})
_rk136["maxItems"] = len(_rk136["items"]["enum"])
# Stripe live mode (owner 2026-11-21 "Yes, build live mode now (Recommended)"): the server's Stripe mode for the admin.
S["StripeStatus"] = obj({
    "mode": s(enum=["live", "test", "off"]),
    "reason": s("Only with mode off.", enum=["no_keys", "keys_incomplete", "mixed_keys", "bad_webhook_secret", "test_keys_in_production", "live_keys_outside_production"])},
    ["mode"], _V136 + _SF["status"], addl=False)
op("get", "/admin/payments/stripe-status", "adminStripeStatus", "The server's Stripe mode (live, test or off)", ["admin"], "Admin · Money",
   ok=(200, "StripeStatus"), read_only=True, permission="finance.read", desc=_V136 + _SF["status"] + " " + _SF["keys"])
