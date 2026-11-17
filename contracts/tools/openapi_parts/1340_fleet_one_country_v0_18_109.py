# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.109 (server BQ-FLEETCUR, owner
# 2026-11-15, Rules decisions/session-2026-11-06.md:1322): a fleet works in one country (contract.json
# #driverOnboarding.fleetInvitations.oneCountry): new 409 conflict reason fleet_other_country. Wording only; no shape change
# (the FleetEarnings / GET /driver/fleet/earnings wording comes in through part 1240 from debtModel.driverOwes.fleetEarnings).
_OC = C["driverOnboarding"]["fleetInvitations"]["oneCountry"]
for _p in ("/driver/fleet/join", "/driver/fleet/invite", "/driver/fleet/invitations/{invitationId}/accept",
           "/admin/fleets/{fleetId}/invitations/{invitationId}/accept", "/driver/onboarding"):
    _op = PATHS[_p]["post"]
    assert "fleet_other_country" not in _op.get("description", ""), _p + " v0.18.109 text exists before"
    assert _op["responses"]["409"] == rref("Conflict"), _p + " has a 409"
    _op["description"] = _op.get("description", "") + " " + _OC
_ER = S["Error"]["properties"]["reason"]
_ER["description"] += (" v0.18.109 reason: fleet_other_country (409 conflict, the driver's country is not the fleet's;"
                       " contract.json#driverOnboarding.fleetInvitations.oneCountry).")
