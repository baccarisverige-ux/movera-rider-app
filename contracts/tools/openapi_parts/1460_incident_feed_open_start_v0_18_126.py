# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.126 (S7 W2 Q126 = Q-B4; owner
# 2026-11-15 "Yes, open ones only (Rec.)"): no shape change. The admin alarm feed with no cursor starts from the open
# incidents (contract.json#safety.feedStart); the text is added to GET /admin/incidents/stream.
_o = PATHS["/admin/incidents/stream"]["get"]
assert "v0.18.126" not in _o.get("description", ""), "/admin/incidents/stream v0.18.126 text exists before"
_o["description"] = (_o.get("description", "") + " v0.18.126 (contract.json#safety.feedStart): " + C["safety"]["feedStart"]).strip()
