# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.162 (driver country first; owner
# 2026-11-25 "Yes"): PUT /driver/country (the first-sign-in step), 409 country_required on POST /driver/vehicles,
# POST /admin/drivers/{driverId}/country (reason, audit, fleet rules), the alert kind driver_no_country
# (contract.json#driverCountryFirst).
_DC = C["driverCountryFirst"]
_V162 = "v0.18.162 (contract.json#driverCountryFirst): "
for _p in ("/driver/country", "/admin/drivers/{driverId}/country"):
    assert _p not in PATHS, _p + " exists before v0.18.162"
S["DriverCountryCommand"] = obj({"country": ref("CountryCode")}, ["country"], _V162 + _DC["step"]["route"], addl=False)
op("put", "/driver/country", "setDriverCountry", "Pick the country you work in (first sign-in step)", ["driver"], "Driver · Account",
   body="DriverCountryCommand", ok=(200, "Driver"), mutation=True,
   desc=_V162 + _DC["note"] + " " + " ".join(_DC["step"][k] for k in ("route", "when", "invited")))
S["AdminDriverCountryCommand"] = obj(dict(EV, country=ref("CountryCode"), reason=s(minLength=1, maxLength=500)), ["expectedVersion", "country", "reason"], _V162 + _DC["adminSet"]["route"], addl=False)
op("post", "/admin/drivers/{driverId}/country", "adminSetDriverCountry", "Change a driver's country (reason, audited)", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="AdminDriverCountryCommand", ok=(200, "Driver"), mutation=True, permission="drivers.activate",
   desc=_V162 + " ".join(_DC["adminSet"][k] for k in ("route", "scope", "rules", "saves", "cars", "audit")))
_op = PATHS["/driver/vehicles"]["post"]
_op["description"] = (_op.get("description", "") + " " + _V162 + _DC["required"]["rule"]).strip()
_op = PATHS["/driver/onboarding"]["post"]
_op["description"] = (_op.get("description", "") + " " + _V162 + _DC["step"]["onboarding"]).strip()
S["Driver"]["properties"]["country"]["description"] += " " + _V162 + "missing while the driver has not picked his country; the driver app then shows the country step, the admin the red error. " + _DC["noCountryError"]
