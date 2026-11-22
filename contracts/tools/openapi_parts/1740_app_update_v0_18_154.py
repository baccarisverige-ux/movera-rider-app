# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.154 (P16c minimum app version;
# owner 2026-11-21 20:30 "Yes, build it now (Recommended)", Rules plan/NUMBERS.md P16c): AppUpdate.minVersion and
# AppUpdate.storeUrls per platform in both app documents (contract.json#appUpdate), the X-App-Version / X-App-Platform
# headers, and 426 upgrade_required on booking, go-online and offer accept. Additive.
_AU = C["appUpdate"]
_V154 = "v0.18.154 (contract.json#appUpdate): "
_A = S["AppUpdate"]["properties"]
assert "minVersion" not in _A and "storeUrls" not in _A, "AppUpdate.minVersion / storeUrls exist before v0.18.154"
_SEMVER = r"^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})$"
_ver = {"oneOf": [s(pattern=_SEMVER), {"type": "null"}]}
_url = {"oneOf": [s(format="uri", pattern="^https://", maxLength=500), {"type": "null"}]}
_A["minVersion"] = obj({"android": _ver, "ios": _ver}, desc=_V154 + _AU["fields"] + " " + _AU["scope"] + " " + _AU["validation"], addl=False)
_A["storeUrls"] = obj({"android": _url, "ios": _url}, desc=_V154 + _AU["fields"], addl=False)
S["AppUpdate"]["description"] += " " + _V154 + _AU["note"] + " " + _AU["apps"]
PARAMS["AppVersionHeader"] = {"name": "X-App-Version", "in": "header", "required": False, "description": _V154 + _AU["headers"] + " " + _AU["missingHeader"],
                              "schema": {"type": "string", "pattern": _SEMVER}}
PARAMS["AppPlatformHeader"] = {"name": "X-App-Platform", "in": "header", "required": False, "description": _V154 + _AU["headers"],
                               "schema": {"type": "string", "enum": ["android", "ios"]}}
RESP["UpgradeRequired"] = err("upgrade_required (HTTP 426), reason app_update_required: this app version is below the zone's minimum. " + _AU["server"])
for _p, _m in (("/trips", "post"), ("/driver/availability", "post"), ("/offers/{offerId}/accept", "post")):
    _o = PATHS[_p][_m]
    assert "426" not in _o["responses"], _p + " has a 426 before v0.18.154"
    _o["parameters"] = _o.get("parameters", []) + [pref("AppVersionHeader"), pref("AppPlatformHeader")]
    _o["responses"]["426"] = rref("UpgradeRequired")
    _o["description"] = _o.get("description", "") + " " + _V154 + _AU["server"] + " " + _AU["neverRefused"]
_rk = S["ConfigDraftUpdate"]["properties"]["removeKeys"]
_KK154 = C["configDocs"]["keptKeys"]
_rk["items"]["enum"] = sorted(set(_rk["items"]["enum"]) | set(_KK154["rider_app_config"]) | set(_KK154["driver_app_config"]))
_rk["maxItems"] = len(_rk["items"]["enum"])
PATHS["/admin/config/{doc}"]["put"]["description"] += " v0.18.154 (configDocs.keptKeys; rider_app_config and driver_app_config: appUpdate.minVersion, appUpdate.storeUrls): " + _KK154["appUpdateNote"]
