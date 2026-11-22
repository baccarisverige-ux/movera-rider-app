# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.140 (owner 2026-11-19
# "Yes, build M2 + M3 (Rec.)", M3): CompletePreview.cashDueRide + cashDueOutstandingFee (contract.json#completePreview.cashDueSplit).
# Additive, optional; display only.
_CDS = C["completePreview"]["cashDueSplit"]
_CP = S["CompletePreview"]["properties"]
assert "cashDueRide" not in _CP and "cashDueOutstandingFee" not in _CP, "CompletePreview split exists before"
_CP["cashDueRide"] = {"allOf": [ref("Money")], "description": _CDS}
_CP["cashDueOutstandingFee"] = {"allOf": [ref("Money")], "description": _CDS}
