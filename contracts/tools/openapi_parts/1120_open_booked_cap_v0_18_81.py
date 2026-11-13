# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.81 (server B1.34, owner Q94 "A) Yes",
# 2026-11-13: default 3): at most DriverAppConfig.reservations.maxOpenPerRider open booked rides per rider; the next
# POST /trips kind scheduled -> 409 conflict, reason booked_rides_limit (contract.json#bookLater.riderCap).
_cap = C["bookLater"]["riderCap"]
S["DriverReservations"]["properties"]["maxOpenPerRider"] = dflt(i(_cap, minimum=1, maximum=50), C["configDefaults"]["reservations"]["maxOpenPerRider"])
_op = PATHS["/trips"]["post"]
assert _op["responses"]["409"] == rref("Conflict"), "POST /trips 409 changed before v0.18.81"
_op["responses"]["409"] = err("version_mismatch / invalid_transition (with projection) or conflict (active_trip_exists, quote_used, quote_expired, ...). "
                              "v0.18.81 (B1.34): kind scheduled and the rider already holds maxOpenPerRider booked rides that have not ended "
                              "→ conflict, reason booked_rides_limit, the number in the message (contract.json#bookLater.riderCap).", "ConflictError")
