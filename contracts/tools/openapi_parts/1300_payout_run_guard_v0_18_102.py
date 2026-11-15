# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.102 (BQ-V38 stale-approve
# guard; owner item 105 / Q-M8 "Refresh, approve again (Rec.)", Rules decisions/session-2026-11-06.md:1119): approving a
# manual payout run carries what the admin saw (expectedCount + expectedTotal); a changed run = 409 run_changed with the
# fresh PayoutRunCard (contract.json#payoutMode.approveGuard).
_AG = C["payoutMode"]["approveGuard"]
_CMD = S["PayoutRunApproveCommand"]
assert "expectedCount" not in _CMD["properties"], "PayoutRunApproveCommand.expectedCount exists before v0.18.102"
_CMD["properties"]["expectedCount"] = i("v0.18.102 (payoutMode.approveGuard): how many payouts of the run the admin saw.", minimum=1)
_CMD["properties"]["expectedTotal"] = arr(ref("Money"), minItems=1, description="v0.18.102 (payoutMode.approveGuard): the run's Payout.amount summed per currency as the admin saw it, one Money per currency.")
_CMD["required"] = _CMD["required"] + ["expectedCount", "expectedTotal"]
S["PayoutRunCard"] = obj({"country": s(), "periodEnd": ref("Timestamp"), "count": i(minimum=0), "total": arr(ref("Money"))}, ["country", "periodEnd", "count", "total"],
                         "v0.18.102: " + _AG["card"] + " Sent as Error.projection with 409 conflict, reason run_changed.")
PATHS["/admin/payouts/runs/approve"]["post"]["description"] += " " + _AG["note"]
