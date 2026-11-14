# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.90 (BQ-M21; owner 2026-11-13
# 23:42 UTC "Movera commission is how much movera keep"): on a reassigned trip the lost driver's payment is taken off
# what Movera keeps (contract.json#moneyBase.lostDriverPaid). Additive field only.
_LD = C["moneyBase"]["lostDriverPaid"]
assert "lostDriverPaid" not in S["MoneySplit"]["properties"], "MoneySplit.lostDriverPaid exists before v0.18.90"
S["MoneySplit"]["properties"]["lostDriverPaid"] = {"allOf": [ref("Money")], "description": "v0.18.90: " + _LD["rule"] + " " + _LD["kpi"]}
