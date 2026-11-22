# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.130 (SCS guard re-check
# follow-up; owner 2026-11-17 Q-SCS-1 "Keep values, save rest (Rec.)"): configDocs.keptKeys gets the driver document
# (realtime.oneStream, v0.18.122). Additive: removeKeys may name it; the PUT text names it.
_KK130 = C["configDocs"]["keptKeys"]
_rk = S["ConfigDraftUpdate"]["properties"]["removeKeys"]
assert "realtime.oneStream" not in _rk["items"]["enum"], "removeKeys names realtime.oneStream before v0.18.130"
_rk["items"]["enum"] = sorted(set(_rk["items"]["enum"]) | set(_KK130["driver_app_config"]))
_rk["maxItems"] = len(_rk["items"]["enum"])
# v0.18.154: the appUpdate kept keys of the driver document are named by part 1740, not here.
PATHS["/admin/config/{doc}"]["put"]["description"] += " v0.18.130 (configDocs.keptKeys; driver_app_config: " + ", ".join(p for p in _KK130["driver_app_config"] if not p.startswith("appUpdate.")) + "): " + _KK130["driverAppConfigNote"]
