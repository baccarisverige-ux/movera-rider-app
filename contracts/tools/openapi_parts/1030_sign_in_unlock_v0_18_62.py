# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.62 §84: POST /admin/auth/sign-in-locks/unlock documented as the server answers (no behaviour change).
_SU = C["signInUnlock"]
S["SignInUnlockResult"] = {"type": "object", "additionalProperties": False, "required": ["phone", "lifted"],
                           "description": _SU["answer"],
                           "properties": {"phone": {"$ref": "#/components/schemas/PhoneE164"},
                                          "lifted": {"type": "integer", "minimum": 0}}}
_op = PATHS["/admin/auth/sign-in-locks/unlock"]["post"]
_op["x-permission"] = "settings.edit"
_op["responses"].pop("404", None)  # the server never answers 404 here
_ok = _op["responses"]["200"]
_ok["description"] = "The lock is lifted: { phone, lifted }."
_ok["content"] = {"application/json": {"schema": {"$ref": "#/components/schemas/SignInUnlockResult"}}}
_op["description"] = (_op.get("description", "") + " v0.18.62 §84: " + " ".join(_SU[k] for k in ("permission", "answer", "errors"))).strip()
