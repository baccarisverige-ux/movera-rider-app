# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.118 (the contract text recent jobs
# owed): wording in contract.json (debtModel.driverOwes.paidMovera / owed, onTrip.rideCheck long_stop / off_route /
# stopMinutes, driverHome.locationSend.rideCheckScan, supportDesk.inboxOrder.rule, inAppCalls.callOpenUntil) reaches the
# descriptions through the parts that already read those keys. Here only the one server parameter that was missing:
# GET /admin/config/{doc}/history and POST /admin/config/{doc}/restore take exactly one of zoneId or country
# (contract.json#pricingHistory, #configDocs.scope; Rules audits/impact/country-undo.md; server branch
# claude/rules-email-key-browserstack-f5y0p3-cfgundo fad59d5 src/pricing/routes.ts HistoryQuery / RestoreBody), and a
# history entry of a country's standard names country instead of zoneId (src/config/service.ts configHistory).
_V118 = "v0.18.118 "

# --- History: the query takes zoneId or country (the same parameters as GET /admin/config/{doc})
_hist = PATHS["/admin/config/{doc}/history"]["get"]
_hz = [k for k, p in enumerate(_hist["parameters"]) if p.get("name") == "zoneId" and p.get("in") == "query"]
assert len(_hz) == 1, "GET /admin/config/{doc}/history has its own zoneId query before v0.18.118"
_hist["parameters"][_hz[0]:_hz[0] + 1] = [pref("ConfigZoneId"), pref("ConfigCountry")]

# --- History entry: zoneId for a zone's document, country for a country's standard
_he = S["ConfigHistoryEntry"]
assert "country" not in _he["properties"] and "zoneId" in _he["required"], "ConfigHistoryEntry v0.18.118 change exists before"
_he["properties"]["country"] = ref("CountryCode")
_he["required"] = [f for f in _he["required"] if f != "zoneId"]
_he["description"] += " " + _V118 + "(pricingHistory.list): zoneId for a zone's document, country for a country's standard; exactly one of the two."

# --- Restore: the body takes zoneId or country
_rc = S["ConfigRestoreCommand"]
assert "country" not in _rc["properties"] and "zoneId" in _rc["required"], "ConfigRestoreCommand v0.18.118 change exists before"
_rc["properties"]["country"] = ref("CountryCode")
_rc["required"] = [f for f in _rc["required"] if f != "zoneId"]
_rc["description"] = _V118 + "(pricingHistory.restore, configDocs.scope): exactly one of zoneId or country."
