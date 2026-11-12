# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.76 (G30): an e-mail is saved
# only after a code check; Rider / Driver carry emailVerifiedAt; PATCH /rider/profile no longer takes email; per-country
# admin setting OnboardingSettings.emailVerifiedForApproval (default off) (contract.json#emailVerified).
_EV = C["emailVerified"]
_EVW = _EV["writePaths"]
_EVD = "v0.18.76 (G30): " + _EV["field"]
S["Rider"]["properties"]["emailVerifiedAt"] = {"allOf": [ref("Timestamp")], "description": _EVD}
S["Driver"]["properties"]["emailVerifiedAt"] = {"allOf": [ref("Timestamp")], "description": _EVD}
assert "email" in S["RiderProfileUpdate"]["properties"], "RiderProfileUpdate lost email before v0.18.76"
del S["RiderProfileUpdate"]["properties"]["email"]
S["RiderProfileUpdate"]["description"] = "v0.18.76 (G30): no email here. " + _EVW["riderPatch"]
_op = PATHS["/rider/profile"]["patch"]
_op["description"] = (_op.get("description", "") + " v0.18.76 (G30): " + _EVW["riderPatch"]).strip()
S["DriverOnboardingRequest"]["properties"]["email"]["description"] = "v0.18.76 (G30): " + _EVW["driverSignUp"]
S["AccountEmailVerified"] = obj({"email": s(format="email"), "emailVerifiedAt": ref("Timestamp")}, ["email", "emailVerifiedAt"],
                                "v0.18.76 (G30): the saved, now verified e-mail. " + _EVW["codeChange"])
_op = PATHS["/account/email/verify"]["post"]
_op["responses"]["200"] = {"description": "OK", "headers": HDR_REQ, "content": {"application/json": {"schema": ref("AccountEmailVerified")}}}
_op["description"] += " v0.18.76 (G30): " + _EV["verifyCurrent"] + " " + _EV["unique"]
_op = PATHS["/account/email/change"]["post"]
_op["description"] += " v0.18.76 (G30): " + _EV["verifyCurrent"] + " " + _EV["unique"] + " " + _EV["delivery"]
S["AccountEmailChallenge"]["properties"]["delivery"]["description"] = "v0.18.76 (G30): " + _EV["delivery"]
_op = PATHS["/auth/provider"]["post"]
_op["description"] = (_op.get("description", "") + " v0.18.76 (G30): " + _EVW["provider"]).strip()
S["OnboardingSettings"]["properties"]["emailVerifiedForApproval"] = {**b("v0.18.76 (G30): " + _EV["approvalSetting"]), "default": False}
_op = PATHS["/admin/drivers/{driverId}/status"]["post"]
_op["description"] = (_op.get("description", "") + " v0.18.76 (G30): " + _EV["approvalSetting"] + " " + _EV["neverActive"]).strip()
_op = PATHS["/driver/reminders"]["get"]
_op["description"] += " v0.18.76 (G30): email_not_verified: " + C["driverOnboarding"]["reminders"]["kinds"]["email_not_verified"]
