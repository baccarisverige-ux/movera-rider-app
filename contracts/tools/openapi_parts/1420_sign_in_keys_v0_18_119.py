# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.119 (S7 W2 Q117 + Q118; owner
# 2026-11-15 "Yes, per user (Rec.)" and "Yes, phone + address (Rec.)", 2026-11-16 OQ-1 "Lock at 60 for 24 h (Rec.)" and
# OQ-2 "Keep fixed in server (Rec.)"; Rules audits/impact/s7-q117-q118.md and -supervisor.md MF-3): wording only, no shape
# change. The new auth.otp.note, countryLimits.fields.wrongCodesPerDay and deepFix1.signIn text reaches the unlock call,
# CountryLimits and POST /auth/refresh through the parts that already read those keys. Here the write-limit key
# (contract.json#rateLimit.key) is added to the four calls it now keys by the body, with the 401-not-429 rule.
_RLK = C["rateLimit"]["key"]
_V119 = "v0.18.119 "

for _path in ["/auth/otp/request", "/auth/otp/verify", "/auth/refresh", "/admin/auth/refresh"]:
    _o = PATHS[_path]["post"]
    assert "v0.18.119 (contract.json#rateLimit.key)" not in _o.get("description", ""), _path + " v0.18.119 text exists before"
    _o["description"] = (_o.get("description", "") + " " + _V119 + "(contract.json#rateLimit.key): " + _RLK).strip()

# The wrong-code lock over all addresses is answered on both code calls with the existing reason.
for _path in ["/auth/otp/request", "/auth/otp/verify"]:
    PATHS[_path]["post"]["description"] += " " + _V119 + "(auth.signInErrors.otp_locked_today): " + AU["signInErrors"]["otp_locked_today"]
