# Runs inside tools/gen_openapi.py in name order with its globals. v0.18.141 DRAFT (owner 2026-11-20 "Stripe is used for exactly
# TWO things"): the driver pays his monthly amount owed to Movera with Stripe (contract.json#driverPayRequest.stripe).
_DPS = C["driverPayRequest"]["stripe"]
S["DriverPayMovera"]["properties"]["stripe"] = b("True: the app shows the Stripe Pay button (POST /driver/pay-movera/pay) instead of the link.")
S["StripeDriverPayment"] = obj({
    "paymentIntentId": s(maxLength=255),
    "amount": {"allOf": [ref("Money")], "description": "The server's amount: what he owes Movera now."},
    "status": s(enum=["requires_payment", "processing", "succeeded", "failed", "canceled", "refund_pending", "refunded"]),
    "clientSecret": s("Only to the paying driver while requires_payment.", maxLength=500),
    "publishableKey": s("The Stripe publishable key of the server's mode (pk_test_ or pk_live_, stripeFees.keys), with clientSecret.", maxLength=255),
    "createdAt": ref("Timestamp")},
    ["paymentIntentId", "amount", "status", "createdAt"], _DPS, addl=False)
op("post", "/driver/pay-movera/pay", "payMoveraStripe", "Pay what he owes Movera with Stripe", ["driver"], "Driver · Account",
   ok=(200, "StripeDriverPayment"), mutation=True, desc=_DPS)
