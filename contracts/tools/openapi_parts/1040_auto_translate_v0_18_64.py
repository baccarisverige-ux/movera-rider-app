# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.64 §85 (owner 2026-11-11): chat messages arrive translated.
_AT = C["chat"]["autoTranslate"]
_V64 = "v0.18.64 §85: "
_LANG = ["sv", "fr", "en"]
S["ChatSettings"]["properties"]["autoTranslate"] = {**b(C["chat"]["settings"]["fields"]["autoTranslate"]), "default": C["configDefaults"]["chat"]["autoTranslate"]}
S["ChatOptions"]["properties"]["autoTranslate"] = b(_V64 + _AT["when"] + " Absent (an older server): false.")
S["Message"]["properties"]["lang"] = s(_V64 + _AT["sourceLanguage"], enum=_LANG)
S["TranslateMessageRequest"]["properties"]["auto"] = b(_V64 + _AT["request"])
S["TranslatedMessage"]["description"] = _V64 + _AT["cache"] + " " + _AT["sameLanguage"]
_op = PATHS["/trips/{tripId}/messages/translate"]["post"]
_op["description"] += " " + _V64 + " ".join(_AT[k] for k in ("rule", "request", "sameLanguage", "cache", "failure"))
