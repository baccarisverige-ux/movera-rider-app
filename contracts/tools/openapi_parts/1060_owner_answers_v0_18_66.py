# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.66 §87: call connect
# timeout as an admin setting (contract.json#callConnect) and the admin trip chat's kept translations
# (contract.json#chat.autoTranslate.adminView).
_CC = C["callConnect"]
_CT = _CC["connectTimeout"]
_CTR = C["inAppCalls"]["settings"]["ranges"]["connectTimeoutSeconds"]
_CTD = C["configDefaults"]["calls"]["connectTimeoutSeconds"]
S["CountryRules"]["properties"]["calls"]["properties"]["connectTimeoutSeconds"] = {
    **i("v0.18.66 §87: " + _CT["setting"] + " " + _CT["admin"] + " " + _CT["rule"], minimum=_CTR[0], maximum=_CTR[1]), "default": _CTD}
for _n, _who in (("TripCall", "mode in_app"), ("CallView", "every CallView")):
    S[_n]["properties"]["connectTimeoutSeconds"] = {
        **i("v0.18.66 §87, " + _who + ": the trip zone's CountryRules.calls.connectTimeoutSeconds. " + _CT["delivery"], minimum=_CTR[0], maximum=_CTR[1]),
        "default": _CTD}
S["MessageTranslation"] = obj({"to": s(enum=C["auth"]["firstLanguage"]["supported"]), "text": s(minLength=1)}, ["to", "text"],
                              "v0.18.66 §87: one translation the server keeps for a message (trip_message_translations).")
S["Message"]["properties"]["translations"] = {**arr(ref("MessageTranslation")),
                                              "description": "v0.18.66 §87, admin reads only: " + C["chat"]["autoTranslate"]["adminView"]}
_op = PATHS["/trips/{tripId}/messages"]["get"]
_op["description"] += " v0.18.66 §87: answered to an admin, each Message carries translations (the kept translations, read-only; never a new provider call). Rider and driver answers never carry translations."
_op = PATHS["/trips/{tripId}/call"]["post"]
_op["description"] += " v0.18.66 §87: TripCall.connectTimeoutSeconds (CountryRules.calls, default 25)."
