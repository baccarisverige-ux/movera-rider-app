# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.165 (owner 2026-11-25 "Mail 90 s",
# Rules decisions/session-2026-11-06.md): the account e-mail change code lives auth.emailCode.expiresSeconds (90 s) and a new
# one may be asked after auth.emailCode.retryAfterSeconds (90 s); earlier is 429 rate_limited reason otp_resend_too_soon.
_EC165 = C["auth"]["emailCode"]
assert _EC165["expiresSeconds"] == 90 and _EC165["retryAfterSeconds"] == 90, "e-mail change code 90 s from v0.18.165"
PATHS["/account/email/change"]["post"]["description"] += (
    " v0.18.165 (auth.emailCode): the e-mail code lives %d s (expiresAt; after it verify is 410 otp_expired) and a new code for the same address"
    " may be asked %d s after the last one for it; earlier is 429 rate_limited reason otp_resend_too_soon with Retry-After (no mail sent)."
    % (_EC165["expiresSeconds"], _EC165["retryAfterSeconds"]))
