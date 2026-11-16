# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.111 (server BQ-M28; M28 supervisor
# MF3, Rules audits/impact/m28-late-bonus-supervisor.md §3.4): a paid trip's own later bonus lowers Movera gets once, in the
# payout that pays it (contract.json#priceDisplay.payoutSummary.laterBonus). Wording only (the new rule and frozenWhenPaid
# texts come in through parts 1190 and 1220). Also BQ-M29 (Rules audits/impact/m29-late-adjustment.md): the same rule for the
# trip's own pay-change entries (contract.json#priceDisplay.payoutSummary.laterPayChange).
_LB = C["priceDisplay"]["payoutSummary"]["laterBonus"]
S["PayoutSummary"]["description"] = S["PayoutSummary"]["description"] + " " + _LB + " " + C["priceDisplay"]["payoutSummary"]["laterPayChange"]
