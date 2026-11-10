# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.58 §80 (owner 2026-11-10): counts-as-arrived distance per zone.
AD58 = C["arrivedDistance"]
_R58 = C["finish"]["earlyEnd"]["settings"]["ranges"]
_D58 = C["configDefaults"]["earlyEnd"]
_V58 = "v0.18.58 §80: "
for _k in ("arrivedWithinMeters", "airportArrivedWithinMeters"):
    S["EarlyEndSettings"]["properties"][_k] = {**i(_V58 + AD58["fields"] + " " + (AD58["airport"] if _k.startswith("airport") else AD58["rule"]), minimum=_R58[_k][0], maximum=_R58[_k][1]), "default": _D58[_k]}
_CP = S["CompletePreview"]["properties"]
_CP["arrivedLimitMeters"] = i(_V58 + AD58["projection"], minimum=0)
_CP["distanceToDropoffMeters"] = i(_V58 + AD58["projection"], minimum=0)
_CP["earlyEnd"]["description"] = _V58 + AD58["rule"]
