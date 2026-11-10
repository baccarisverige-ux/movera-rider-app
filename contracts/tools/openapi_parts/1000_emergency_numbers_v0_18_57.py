# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.57 §79 (owner 2026-11-10): emergency numbers per country.
EN57 = C["emergencyNumbers"]
_V57 = "v0.18.57 §79: "
_L40 = obj({"sv": s(minLength=1, maxLength=40), "fr": s(minLength=1, maxLength=40), "en": s(minLength=1, maxLength=40)}, ["sv", "fr", "en"])
S["EmergencyNumber"] = obj({"kind": s(enum=EN57["kinds"]), "number": s(pattern="^\\+?[0-9]{2,15}$"), "label": _L40},
                           ["kind", "number", "label"], _V57 + EN57["item"])
S["CountryRules"]["properties"]["emergencyNumbers"] = {**arr(ref("EmergencyNumber"), minItems=1, maxItems=6),
    "description": _V57 + EN57["where"] + " " + EN57["defaults"] + " " + EN57["validation"]}
for _cfg in ("RiderAppConfig", "DriverAppConfig"):
    S[_cfg]["properties"]["emergencyNumbers"] = {**arr(ref("EmergencyNumber"), minItems=1, maxItems=6),
        "description": _V57 + EN57["apps"] + " " + EN57["screens"]}
