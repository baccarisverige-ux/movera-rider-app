# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.49 §71 owner decisions Q6–Q13.
AU49 = C["auth"]
_so = PATHS["/auth/sign-out"]["post"]
_so["description"] = (_so.get("description", "") + " " + AU49["signOutOnTrip"]["rule"]).strip()
_rs = OrderedDict()
for _k, _v in _so["responses"].items():
    _rs[_k] = _v
    if _k == "404": _rs["409"] = rref("Conflict")
_so["responses"] = _rs
_rf = PATHS["/auth/refresh"]["post"]
_rf["description"] = _rf.get("description", "") + " " + AU49["tokens"]["lostAnswer"]["rule"] + " " + AU49["tokens"]["lostAnswer"]["once"]
_fc = " v0.18.49 §71 (owner Q10): the free-CHANGE window only; a booked ride's cancel is free only inside the category's reservation cancel fee freeMin (" + C["bookLater"]["rider"]["cancel"] + ")"
S["DriverReservations"]["properties"]["freeChangeBeforeMin"]["description"] += _fc
S["RiderAppConfig"]["properties"]["booking"]["properties"]["freeChangeBeforeMin"]["description"] += _fc
