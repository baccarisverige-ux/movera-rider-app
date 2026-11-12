# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.77 (G30, owner 2026-11-12 ~15:02
# "Max 10 tries/hour"): besides the 3 accepted e-mail code sends per hour, at most 10 e-mail code starts per hour per account,
# counting every start (sent or pending_provider); over it 429 change_too_many (contract.json#emailVerified.delivery).
_op = PATHS["/account/email/change"]["post"]
assert _op["responses"]["429"] == rref("RateLimited"), "POST /account/email/change 429 changed before v0.18.77"
_op["responses"]["429"] = err("rate_limited, reason change_too_many; obey Retry-After. v0.18.77 (G30): at most 3 accepted code sends "
                              "(delivery 'sent') AND at most 10 code starts (every start, sent or pending_provider) per hour per account; "
                              "whichever is reached first refuses, before any e-mail is sent (contract.json#emailVerified.delivery).",
                              headers={"Retry-After": {"schema": {"type": "integer", "minimum": 0}}})
