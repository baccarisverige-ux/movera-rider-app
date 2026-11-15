# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.95 (server BQ-M26; M24 supervisor
# N1): a paid payout's summary is frozen when it is marked paid (contract.json#priceDisplay.payoutSummary.frozenWhenPaid).
# Wording only: the PayoutSummary description says so.
_FZ = C["priceDisplay"]["payoutSummary"]["frozenWhenPaid"]
S["PayoutSummary"]["description"] = S["PayoutSummary"]["description"] + " " + _FZ
