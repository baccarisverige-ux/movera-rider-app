# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.152 (owner 2026-11-21 15:00 (A) +
# (B), Rules decisions/session-2026-11-06.md "2026-11-21 15:15 OWNER DECISION (booked rides, rider screens)"): wording
# plus one optional property already sent. GET /rider/trips/active also returns a booked trip being searched or accepted
# that no list driver ever held (contract.json#bookedRideSeen.searchSeen); TripProjection.driverAssigned (rider view,
# bookLater.liveFixes.driverShown) is described.
_ACT = PATHS["/rider/trips/active"]["get"]
assert "v0.18.152" not in _ACT["description"], "active trip v0.18.152 text exists before"
_ACT["description"] = _ACT["description"] + (" v0.18.152 (contract.json#bookedRideSeen.searchSeen): also a booked trip in searching, offered or"
    " accepted that no list driver holds or ever held (its search started: 30 min before the pickup, or at once when booked"
    " under 30 min ahead): the rider app shows the normal Finding driver and driver screens, the driver at accept. A ride a"
    " list driver holds, or gave back before driving, is not returned before driver_to_pickup.")
_TP = S["TripProjection"]["properties"]
assert "driverAssigned" not in _TP, "TripProjection.driverAssigned exists before"
_TP["driverAssigned"] = {"type": "boolean", "description": "Rider view only. v0.18.19 Owner D / v0.18.152 (contract.json#bookLater.liveFixes.driverShown):"
    " true while a list driver holds this booked ride (status accepted), or one held it before; then driver and driverLocation are"
    " not sent until driver_to_pickup. Absent otherwise (a booked ride no list driver ever held shows its driver at accept)."}
