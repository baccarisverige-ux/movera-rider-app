# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.106 (contract text batch,
# wording only): POST /admin/drivers/{driverId}/paid-movera names its 400 reasons (J8 supervisor W1, Rules
# audits/impact/j8-rebase-money-fix-supervisor.md; server src/admin/driversOwing.ts). The paid-movera description
# (debtModel.driverOwes.paidMovera) and HeadingCheckSettings (pickupWaiting.headingCheck.setting) take the new
# wording from contract.json through parts 1150 and 0500.
PATHS["/admin/drivers/{driverId}/paid-movera"]["post"]["responses"]["400"] = err(
    "invalid_request: malformed body, unknown enum, wrong reasonCode group, bad PIN. v0.18.106 (debtModel.driverOwes.paidMovera):"
    " reason invalid_amount (amount ≤ 0), currency_mismatch (amount in another currency than expectedOwed),"
    " paid_above_owed (amount above the owed now), reason_required (reason not 1..300 characters).")
