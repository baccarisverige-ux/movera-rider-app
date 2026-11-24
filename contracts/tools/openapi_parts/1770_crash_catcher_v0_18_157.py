# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.157 (crash catcher; owner
# 2026-11-24 "Add to admin all kind of crash", Rules LAUNCH-RULE.md 2026-11-24, plan/NUMBERS.md): the new kinds and
# optional fields of POST /telemetry/crashes, the kind filter of GET /admin/errors, GET /admin/errors/{errorId}/reports,
# RiderAppConfig / DriverAppConfig crashReports { on } (contract.json#crashCatcher). Additive.
_CC = C["crashCatcher"]
_V157 = "v0.18.157 (contract.json#crashCatcher): "
_T = S["TelemetryCrash"]["properties"]
for _k in ("osVersion", "deviceModel", "tripId", "zoneId", "breadcrumbs", "nativeReason", "freezeMs"):
    assert _k not in _T, "TelemetryCrash." + _k + " exists before v0.18.157"
_BC = _CC["breadcrumbs"]
S["CrashBreadcrumb"] = obj(OrderedDict([("at", ref("Timestamp")), ("type", s(enum=_BC["types"])), ("message", s(maxLength=_BC["maxMessage"]))]),
                           ["at", "type", "message"], _V157 + _BC["rule"], addl=False)
S["NativeCrashReason"] = obj(OrderedDict([("name", s(maxLength=200)), ("reason", s(maxLength=1000))]), ["name"], _V157 + _CC["nativeReason"], addl=False)
_T["kind"]["description"] = _T["kind"]["description"] + " " + _V157 + " ".join(f"{k}: {v}" for k, v in _CC["kinds"].items())
_T["osVersion"] = s(_V157 + "e.g. iOS 17.1, Android 14 (API 34).", maxLength=60)
_T["deviceModel"] = s(_V157 + "e.g. iPhone15,2, samsung SM-S911B.", maxLength=80)
_T["tripId"] = s(_V157 + "the trip on screen, when there is one.", maxLength=64)
_T["zoneId"] = s(_V157 + "the zone the app is in.", maxLength=64)
_T["breadcrumbs"] = arr(ref("CrashBreadcrumb"), maxItems=_BC["max"], description=_V157 + _BC["rule"])
_T["nativeReason"] = {"allOf": [ref("NativeCrashReason")], "description": _V157 + "native_crash only."}
_T["freezeMs"] = i(_V157 + "freeze only: how long the screen froze.", minimum=0)
S["TelemetryCrash"]["description"] += " " + _V157 + _CC["fields"] + " " + _CC["outbox"] + " " + _CC["server"]["perDevice"]
S["ErrorGroup"]["properties"]["kind"]["description"] = _V157 + "the latest report's kind."
_r = OrderedDict([("at", ref("Timestamp")), ("kind", s(enum=C["telemetry"]["crashReport"]["kinds"])),
                  ("appVersion", s(maxLength=40)), ("build", s(maxLength=40)), ("platform", s(enum=C["telemetry"]["crashReport"]["platforms"])),
                  ("osVersion", s(maxLength=60)), ("deviceModel", s(maxLength=80)), ("screen", s(maxLength=200)),
                  ("tripId", s(maxLength=64)), ("zoneId", s(maxLength=64)), ("message", s(maxLength=4000)), ("stack", s(maxLength=12000)),
                  ("nativeReason", ref("NativeCrashReason")), ("freezeMs", i(minimum=0)), ("breadcrumbs", arr(ref("CrashBreadcrumb"), maxItems=_BC["max"]))])
S["ErrorReport"] = obj(_r, ["at", "kind", "message", "breadcrumbs"], _V157 + _CC["admin"]["reports"])
S["ErrorReportList"] = obj({"items": arr(ref("ErrorReport"))}, ["items"], _V157 + "newest first.")
_g = PATHS["/admin/errors"]["get"]
_g["parameters"].insert(len(_g["parameters"]) - 2, q("kind", s(enum=C["telemetry"]["crashReport"]["kinds"]), _V157 + _CC["admin"]["list"]))
_g["description"] += " " + _V157 + _CC["admin"]["list"]
op("get", "/admin/errors/{errorId}/reports", "adminListErrorReports", "The kept reports of one crash or error group (newest first)", ["admin"], "Admin · System",
   params=[pref("ErrorId"), q("limit", {"type": "integer", "minimum": 1, "maximum": 50, "default": 20})], ok=(200, "ErrorReportList"),
   desc=_V157 + _CC["admin"]["reports"] + " Permission: " + C["telemetry"]["errorGroups"]["permission"] + ".")
_ST157 = _CC["setting"]
for _doc in ("RiderAppConfig", "DriverAppConfig"):
    assert "crashReports" not in S[_doc]["properties"], _doc + ".crashReports exists before v0.18.157"
    S[_doc]["properties"]["crashReports"] = obj({"on": {**b("The zone's switch."), "default": C["configDefaults"]["crashReportsOn"]}},
                                               desc=_V157 + _ST157["rule"], addl=False)
