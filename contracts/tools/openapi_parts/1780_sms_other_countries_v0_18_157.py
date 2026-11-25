# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.157 (owner 2026-11-24 "SMS
# sign-in codes must work for ANY phone number from ANY country"): one optional CountryRules field on the home country
# standard (contract.json#smsSignIn.otherCountries) and wording on the code request. No new route.
_OC = C["smsSignIn"]["otherCountries"]
_V157 = "v0.18.157 (contract.json#smsSignIn.otherCountries): "
assert "smsSignInOtherCountries" not in S["CountryRules"]["properties"], "CountryRules.smsSignInOtherCountries exists before v0.18.157"
S["CountryRules"]["properties"]["smsSignInOtherCountries"] = obj(OrderedDict([
    ("enabled", {**b("Real SMS sign-in codes in the rider app for numbers of every country not served on this server (default on)."), "default": C["configDefaults"]["smsSignInOtherCountries"]["enabled"]}),
    ("dailyCap", i("Sign-in SMS per 24 hours to all other-country numbers together before new codes are refused (sms_daily_limit).",
                   minimum=C["smsSignIn"]["dailyCapRange"][0], maximum=C["smsSignIn"]["dailyCapRange"][1], default=C["configDefaults"]["smsSignInOtherCountries"]["dailyCap"])),
    ("perCodeDailyCap", i("Sign-in SMS per 24 hours per calling code inside the other-countries bucket (sms_daily_limit).",
                   minimum=_OC["perCodeDailyCapRange"][0], maximum=_OC["perCodeDailyCapRange"][1], default=C["configDefaults"]["smsSignInOtherCountries"]["perCodeDailyCap"])),
    ("perMinuteCap", i("All sign-in SMS of the server per minute (burst limit, sms_daily_limit).",
                   minimum=_OC["perMinuteCapRange"][0], maximum=_OC["perMinuteCapRange"][1], default=C["configDefaults"]["smsSignInOtherCountries"]["perMinuteCap"])),
    ("blockedCallingCodes", {"type": "array", "maxItems": 50, "uniqueItems": True, "default": [], "description": "Calling codes blocked for other-country numbers (empty by default).", "items": {"type": "string", "enum": _OC["callingCodes"]}}),
]), [], _V157 + _OC["setting"], addl=False)
_op157 = PATHS["/auth/otp/request"]["post"]
_op157["description"] = (_op157.get("description", "") + " " + _V157 + _OC["served"] + " " + _OC["active"] + " " + _OC["numberCheck"]).strip()
