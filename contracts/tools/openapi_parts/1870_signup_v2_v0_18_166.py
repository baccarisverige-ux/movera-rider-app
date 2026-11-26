# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.166 (sign-up pro v2 + document
# scan; owner 2026-11-26 "Oui, tout construire"): PUT /driver/country takes an optional cityId (Région), the Swedish
# personalNumber and taxiLicenseNumber on POST /driver/onboarding and Driver, OnboardingSettings.signUpFields and
# OnboardingSettings.twoSidedTypes (contract.json#signupV2).
_SV = C["signupV2"]
_V166 = "v0.18.166 (contract.json#signupV2): "
_DCC = S["DriverCountryCommand"]["properties"]
assert "cityId" not in _DCC, "DriverCountryCommand.cityId exists before v0.18.166"
_DCC["cityId"] = s(_V166 + "optional Région. " + _SV["regionStep"]["route"], minLength=1, maxLength=64)
_op = PATHS["/driver/country"]["put"]
_op["description"] = (_op.get("description", "") + " " + _V166 + _SV["regionStep"]["route"]).strip()
_OR = S["DriverOnboardingRequest"]["properties"]
_DR = S["Driver"]["properties"]
for _k in ("personalNumber", "taxiLicenseNumber"):
    assert _k not in _OR and _k not in _DR, _k + " exists before v0.18.166"
_PN = _SV["personalNumber"]
_OR["personalNumber"] = s(_V166 + "Sweden (signUpFields). " + _PN["format"] + " " + _PN["dateOfBirth"], pattern=r"^\d{8}-?\d{4}$")
_OR["taxiLicenseNumber"] = s(_V166 + _SV["taxiLicenseNumber"], minLength=1, maxLength=30)
_DR["personalNumber"] = s(_V166 + _PN["stored"])
_DR["taxiLicenseNumber"] = s(_V166 + _SV["taxiLicenseNumber"])
_op = PATHS["/driver/onboarding"]["post"]
_op["description"] = (_op.get("description", "") + " " + _V166 + _SV["signUpFields"]["note"] + " " + _PN["dateOfBirth"]).strip()
_OS = S["OnboardingSettings"]["properties"]
for _k in ("signUpFields", "twoSidedTypes"):
    assert _k not in _OS, "OnboardingSettings." + _k + " exists before v0.18.166"
_FS = obj({"on": b("Shown on the info screen."), "required": b("Must be filled (only when on).")}, ["on", "required"], addl=False)
_OS["signUpFields"] = obj({k: _FS for k in _SV["signUpFields"]["fields"]}, desc=_V166 + _SV["signUpFields"]["note"], addl=False)
_OS["twoSidedTypes"] = arr(ref("DocumentType"), uniqueItems=True, description=_V166 + _SV["twoSided"]["note"] + " " + _SV["twoSided"]["upload"])
# v0.18.166 (owner 2026-11-26 "Peut pas"): an approved profile photo is locked for the driver.
_op = PATHS["/driver/documents"]["post"]
_op["description"] = (_op.get("description", "") + " " + _V166 + C["signupV2"]["profilePhoto"]["locked"]).strip()
# v0.18.166 (owner 2026-11-26 "Oui, ajouter l'adresse (Recommandé)"): the home address (DAC7, invoices).
_AD = C["signupV2"]["address"]
assert "DriverAddress" not in S and "/admin/drivers/{driverId}/address" not in PATHS, "address exists before v0.18.166"
S["DriverAddress"] = obj({"street": s(minLength=1, maxLength=200), "postalCode": s(minLength=1, maxLength=20), "city": s(minLength=1, maxLength=100)},
                         ["street", "postalCode", "city"], _V166 + _AD["owner"] + " " + _AD["shape"] + " " + _AD["autocomplete"], addl=False)
_OR["address"] = ref("DriverAddress")
_DR["address"] = ref("DriverAddress")
_op = PATHS["/driver/onboarding"]["post"]
_op["description"] = (_op["description"] + " " + _V166 + _AD["required"]).strip()
S["AdminDriverAddressCommand"] = obj(dict(EV, address=ref("DriverAddress"), reason=s(minLength=1, maxLength=500)), ["expectedVersion", "address", "reason"], _V166 + _AD["adminEdit"], addl=False)
op("post", "/admin/drivers/{driverId}/address", "adminSetDriverAddress", "Change a driver's home address (reason, audited)", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="AdminDriverAddressCommand", ok=(200, "Driver"), mutation=True, permission="drivers.activate",
   desc=_V166 + _AD["adminEdit"])
