# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.112 (BQ-A04, owner item 109
# "Yes, pages + oldest first (Rec.)", Rules decisions/session-2026-11-06.md:1116): the support inbox lists the
# oldest-waiting ticket first (contract.json#supportDesk.inboxOrder). One new optional admin-view field
# SupportTicket.waitingSince and a new order of GET /admin/tickets; no new query key.
_IO = C["supportDesk"]["inboxOrder"]
_op = PATHS["/admin/tickets"]["get"]
assert "v0.18.112" not in _op["description"], "/admin/tickets v0.18.112 text exists before"
_op["description"] += " v0.18.112 order (contract.json#supportDesk.inboxOrder): " + _IO["rule"] + " " + _IO["paging"]
_ST = S["SupportTicket"]["properties"]
assert "waitingSince" not in _ST, "SupportTicket.waitingSince exists before"
_ST["waitingSince"] = {"allOf": [ref("Timestamp")], "description": "v0.18.112 (contract.json#supportDesk.inboxOrder.waitingSince): " + _IO["waitingSince"]}
