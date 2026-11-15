# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.97 (J8 wording, Rules
# audits/impact/j8-rebase-money-fix-supervisor.md §6): a "Driver paid Movera" entry (paid_to_movera) is never in
# Payout.summary or fleet earnings; paid-movera closing a payout freezes it. Wording only (PayoutSummary.rule and
# frozenWhenPaid come in through parts 1190 and 1220).
_PTM = C["priceDisplay"]["payoutSummary"]["paidToMovera"]
_FE = C["debtModel"]["driverOwes"]["fleetEarnings"]
S["PayoutSummary"]["description"] = S["PayoutSummary"]["description"] + " " + _PTM
S["FleetEarnings"]["description"] = S["FleetEarnings"]["description"] + " " + _FE
PATHS["/driver/fleet/earnings"]["get"]["description"] += " " + _FE
PATHS["/admin/drivers/{driverId}/paid-movera"]["post"]["description"] += (
    " v0.18.97 (priceDisplay.payoutSummary.frozenWhenPaid, paidToMovera): a payout below 0 whose carried rest this money covers"
    " in full is closed as paid (note \"Driver paid Movera\", audit payout.paid) and its Payout.summary is frozen in the same step;"
    " the paid_to_movera entry is never in driverGets or moveraGets.")
