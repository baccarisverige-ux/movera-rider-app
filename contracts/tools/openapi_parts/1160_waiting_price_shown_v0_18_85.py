# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.85 (audit A1; owner 2026-11-02
# "Show price incl. fee (Recommended)", Rules decisions/driver-g6.md:96): the waiting prices with the app fee, as the rider
# pays them (contract.json#waitingPriceShown). Additive fields only; the fare rule is unchanged.
_WPS = C["waitingPriceShown"]
for _k in ("waitPerMinShown", "stopWaitPerMinShown"):
    assert _k not in S["TripTerms"]["properties"], "TripTerms." + _k + " exists before v0.18.85"
    S["TripTerms"]["properties"][_k] = {"allOf": [ref("Money")], "description": "v0.18.85: " + _WPS["fields"]["TripProjection.terms." + _k] + " " + _WPS["rule"]}
for _schema in ("RiderWaiting", "CategoryWaiting"):
    assert "perMinShown" not in S[_schema]["properties"], _schema + ".perMinShown exists before v0.18.85"
    S[_schema]["properties"]["perMinShown"] = {"allOf": [ref("Money")], "description": "v0.18.85: " + _WPS["fields"]["RiderAppConfig.waiting.perMinShown"]
                                               + " The driver app ignores it: " + _WPS["apps"]["driver"]}
