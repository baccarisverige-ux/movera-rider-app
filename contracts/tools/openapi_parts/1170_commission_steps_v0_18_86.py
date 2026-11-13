# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.86 (J5b, owner 2026-11-13 ~20:48 UTC
# "Yes, like this (Rec.)", ~21:40 "Yes, warn (Rec.)", Rules decisions/session-2026-11-06.md): commission steps per zone and car type, each a % or a fixed
# amount, picked by the commission base (contract.json#commissionSteps). Additive: no steps = commissionPct, unchanged.
_CS = C["commissionSteps"]
_V = _CS["validation"]
assert "CommissionStep" not in S and "commissionSteps" not in S["CategoryPricing"]["properties"], "commission steps exist before v0.18.86"
S["CommissionStep"] = obj(OrderedDict([
    ("upToMinor", {"oneOf": [i("\"Trip price up to X\": the commission base in minor units of the document's currency, X included; strictly higher than the step before.", minimum=1), {"type": "null"}],
                   "description": "null = \"above\": allowed, and required, only on the last step."}),
    ("pct", n("Movera's commission in % of the commission base (like commissionPct). Exactly one of pct or amountMinor.", minimum=_V["pctMin"], maximum=_V["pctMax"])),
    ("amountMinor", i("A fixed commission in minor units of the zone currency (TND millimes, 3 decimals); never more than the commission base (capped). Exactly one of pct or amountMinor.", minimum=0)),
]), ["upToMinor"], "v0.18.86 (J5b): one commission step. " + _CS["pick"], addl=False,
    oneOf=[{"required": ["pct"], "not": {"required": ["amountMinor"]}}, {"required": ["amountMinor"], "not": {"required": ["pct"]}}])
_cp = S["CategoryPricing"]["properties"]
_cp["commissionSteps"] = {"oneOf": [arr(ref("CommissionStep"), maxItems=_V["maxSteps"]), {"type": "null"}],
                          "description": "v0.18.86 (J5b, owner 2026-11-13): optional; absent, null or [] = no steps (commissionPct applies, unchanged). " + _CS["field"] + " " + _CS["money"] + " " + _CS["adminPlacement"] + " Warning (admin only): " + _CS["warn"]["advisory"]}
_cp["commissionPct"]["description"] += " v0.18.86: used only when commissionSteps is absent, null or [] (empty) (contract.json#commissionSteps.noSteps)."
_why = (" v0.18.86 (J5b, contract.json#commissionSteps.validation): pricing with invalid CategoryPricing.commissionSteps → invalid_request, "
        "reason commission_steps_invalid, details [\"step:<index>\", \"problem:<code>\"] (" + ", ".join(_V["problems"]) + "); nothing is saved.")
for _m, _p in (("put", "/admin/config/{doc}"), ("post", "/admin/config/{doc}/publish")):
    _op = PATHS[_p][_m]
    assert _op["responses"]["400"] == rref("BadRequest"), _p + " 400 changed before v0.18.86"
    _op["responses"]["400"] = err("invalid_request: malformed body, unknown enum, wrong reasonCode group, bad PIN." + _why)
    _op["description"] += _why
