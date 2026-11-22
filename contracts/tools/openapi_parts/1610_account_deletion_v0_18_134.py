# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.134 (account deletion E1; owner
# button 2026-11-20 "Accept, keep debt (Rec.)", Rules decisions/session-2026-11-06.md): the request closes the account
# at once, a debt never blocks it and is kept as a record, the rest is erased 30 days after the request
# (contract.json#accountDeletion). Additive: two optional fields, one driver route, one admin read, one setting.
_AD = C["accountDeletion"]
_V140 = "v0.18.134 (accountDeletion): "
_ad = S["AccountDeletion"]
assert "requestedAt" not in _ad["properties"], "AccountDeletion.requestedAt exists before v0.18.134"
_ad["properties"]["requestedAt"] = {"allOf": [ref("Timestamp")], "description": _V140 + "when the account asked (the first request)."}
_ad["properties"]["eraseDueAt"] = {"allOf": [ref("Timestamp")], "description": _V140 + "requestedAt + eraseAfterDays: from then the job may erase it."}
_ad["description"] = (_ad.get("description", "") + " " + _V140 + _AD["request"]).strip()
_DESC140 = " ".join(_V140 + _AD[k] for k in ("closeAtOnce", "refused", "debt", "erase", "kept"))
_r140 = PATHS["/account/deletion"]["post"]
_r140["description"] = (_r140.get("description", "") + " " + _DESC140 + " " + _AD["rider"]).strip()
_r140["responses"]["409"] = rref("Conflict")
op("post", "/driver/account/deletion", "requestDriverAccountDeletion", "Ask to delete the driver account", ["driver"], "Driver · Account",
   ok=(202, "AccountDeletion"), mutation=True, ok_desc="Accepted; the account is closed now and erased 30 days later.",
   desc=_DESC140 + " " + _AD["driver"])["responses"]["409"] = rref("Conflict")
S["DeletionRequest"] = obj({
    "accountKind": s(enum=["rider", "driver"]),
    "accountId": ref("Id"),
    "firstName": s("First name while the account is not erased; '' after.", maxLength=100),
    "requestedAt": ref("Timestamp"),
    "eraseDueAt": ref("Timestamp"),
    "status": s(enum=_AD["adminStatus"]),
    "waitingReason": s("Why a due account is not erased yet: erase_off (the setting is off: count only), open_trip, open_safety_case.", enum=["erase_off", "open_trip", "open_safety_case"]),
    "debt": obj({"amount": ref("Money"), "settled": b("Paid or written off: the record goes with the next run.")}, ["amount", "settled"], "The kept debt record (amount only here).", addl=False),
    "erasedAt": ref("Timestamp")},
    ["accountKind", "accountId", "requestedAt", "eraseDueAt", "status"], _V140 + _AD["admin"], addl=False)
S["DeletionRequestPage"] = obj({"items": {"type": "array", "items": ref("DeletionRequest"), "maxItems": 200},
    "dueNow": i("How many accounts are due now (the dry-run count while eraseEnabled is off).", minimum=0)}, ["items", "dueNow"], _V140 + "newest first, at most 200.", addl=False)
op("get", "/admin/deletion-requests", "adminDeletionRequests", "Account deletion requests and their status", ["admin"], "Admin · Riders",
   ok=(200, "DeletionRequestPage"), permission="riders.read", read_only=True, desc=_V140 + _AD["admin"] + " " + _AD["job"])
_DADS = C["configDefaults"]["accountDeletion"]
S["AccountDeletionSetting"] = obj({
    "eraseEnabled": dflt(b("Off = the job only counts (dry-run); on = due accounts are erased."), _DADS["eraseEnabled"]),
    "eraseAfterDays": dflt(i("Days from the request to the erase.", minimum=30, maximum=365), _DADS["eraseAfterDays"])},
    [], _V140 + _AD["setting"], addl=False)
assert "accountDeletion" not in S["CountryRules"]["properties"], "CountryRules.accountDeletion exists before v0.18.134"
S["CountryRules"]["properties"]["accountDeletion"] = ref("AccountDeletionSetting")
