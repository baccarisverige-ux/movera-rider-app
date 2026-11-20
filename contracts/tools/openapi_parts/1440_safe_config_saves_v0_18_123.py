# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.123 (SF-F1-3 safe config saves;
# owner 2026-11-17 Q-SCS-1 "Keep values, save rest (Rec.)", 2026-11-16 Q-SCS-2 "No, keep current (Rec.)"; Rules
# audits/impact/safe-config-saves.md §3): PUT /admin/config/{doc} keeps the listed kept keys a save leaves out
# (contract.json#configDocs.keptKeys), takes an optional removeKeys and answers keptKeys; Restore keeps the live payout and
# debt settings of country_rules (pricingHistory.restoreKeeps); the alert settings save keeps stored kinds
# (alertDesk.commands.settingsKeepKinds). Additive and optional.
_KK = C["configDocs"]["keptKeys"]
_V123 = "v0.18.123 "
_KEPT = sorted({p for d in ("country_rules", "dispatch") for p in _KK[d]})

_u = S["ConfigDraftUpdate"]
assert "removeKeys" not in _u["properties"], "ConfigDraftUpdate.removeKeys exists before v0.18.123"
_u["properties"]["removeKeys"] = arr(s(enum=_KEPT), maxItems=len(_KEPT), description=_V123 + "(configDocs.keptKeys.removeKeys): " + _KK["removeKeys"])
_d = S["ConfigDraft"]
assert "keptKeys" not in _d["properties"], "ConfigDraft.keptKeys exists before v0.18.123"
_d["properties"]["keptKeys"] = arr(s(), description=_V123 + "PUT answer only: the kept keys the server copied from the stored document into this draft (configDocs.keptKeys); absent when none.")

_put = PATHS["/admin/config/{doc}"]["put"]
_put["description"] += " " + _V123 + "(configDocs.keptKeys; country_rules: " + ", ".join(_KK["country_rules"]) + "; dispatch: " + ", ".join(_KK["dispatch"]) + "): " + _KK["note"] + " " + _KK["removeKeys"]
PATHS["/admin/config/{doc}/restore"]["post"]["description"] += " " + _V123 + "(pricingHistory.restoreKeeps): " + C["pricingHistory"]["restoreKeeps"]
PATHS["/admin/alerts/settings"]["put"]["description"] += " " + _V123 + "(alertDesk.commands.settingsKeepKinds): " + C["alertDesk"]["commands"]["settingsKeepKinds"]
