# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.61 §83 (owner 2026-11-11 "Finance permission"): GET /payments/{paymentId} shared by rider and admin.
_PR = C["paymentRead"]
_op = PATHS["/payments/{paymentId}"]["get"]
_op["x-permission"] = "finance.read"
_op["description"] = (_op.get("description", "") + " v0.18.61 §83: " + " ".join(_PR[k] for k in ("rider", "admin", "cashOnly"))
                      + " x-permission applies to admins only.").strip()
