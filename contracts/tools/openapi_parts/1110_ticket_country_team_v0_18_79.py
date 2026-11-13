# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.79 (server B1.33, owner Q93
# "A) Yes"): a ticket without a zone can be assigned / auto-sorted to an admin of its country team. The assign wording comes
# from contract.json#supportDesk.adminCommands.assign; this part only names the country rule in the caller's scope sentence.
_op = PATHS["/admin/tickets/{ticketId}/assign"]["post"]
_old = " The admin's zones only (else 403 zone_out_of_scope)."
assert _op["description"].endswith(_old), "assign scope sentence changed before v0.18.79"
_op["description"] = _op["description"][: -len(_old)] + (" The admin's zones only; a ticket without a zone: an admin with a zone in its country,"
                                                          " or all zones (contract.json#supportDesk.countryTeam); else 403 zone_out_of_scope.")
