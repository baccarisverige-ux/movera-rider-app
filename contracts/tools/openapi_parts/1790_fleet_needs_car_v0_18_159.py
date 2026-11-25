# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.159 (fleet needs a car; owner
# 2026-11-24, Rules decisions/driver-g2.md "Fleet owner must add a car"): the reminder fleet_no_car (enum from contract.json),
# OnboardingSettings.fleetNeedsCarForApproval (default true), 409 fleet_has_no_car on fleet approval (contract.json#fleetNeedsCar).
_FNC = C["fleetNeedsCar"]
assert "fleet_no_car" in S["DriverReminder"]["properties"]["kind"]["enum"], "DriverReminder kind fleet_no_car from contract.json"
S["OnboardingSettings"]["properties"]["fleetNeedsCarForApproval"] = {**b("v0.18.159 (fleetNeedsCar): " + _FNC["setting"]), "default": True}
_op = PATHS["/admin/fleets/{fleetId}/review"]["post"]
_op["description"] = (_op.get("description", "") + " v0.18.159 (fleetNeedsCar): " + _FNC["refusal"]).strip()
_op = PATHS["/driver/reminders"]["get"]
_op["description"] += " v0.18.159 (fleetNeedsCar): fleet_no_car: " + C["driverOnboarding"]["reminders"]["kinds"]["fleet_no_car"]
S["Fleet"]["properties"]["approvalBlockedReason"] = s("v0.18.159 (fleetNeedsCar.adminView): " + _FNC["adminView"], enum=["fleet_has_no_car"])
