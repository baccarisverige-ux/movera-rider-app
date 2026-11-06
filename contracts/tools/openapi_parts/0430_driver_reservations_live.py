# v0.18.45 §68 (driver booked-rides live hint, contract.json#driverReservationsLive): GET /driver/config/stream also carries driver_reservations_changed.
# A part of tools/gen_openapi.py (rule 25 split), run in name order with its globals, after 0100 defines the op.
DRL = C["driverReservationsLive"]
PATHS["/driver/config/stream"]["get"]["description"] = (PATHS["/driver/config/stream"]["get"].get("description", "") + " v0.18.45 §68: also carries " + DRL["kind"] + " { eventId, kind, tripId, occurredAt, serverTime }. " + DRL["hintOnly"] + " " + DRL["when"] + " " + DRL["app"]).strip()
S["DriverReservationsChangedEvent"] = obj({"eventId": ref("Id"), "kind": s(const=DRL["kind"]), "tripId": ref("Id"),
                                           "occurredAt": ref("Timestamp"), "serverTime": ref("Timestamp")},
                                          ["eventId", "kind", "tripId", "occurredAt", "serverTime"],
                                          "v0.18.45 §68: hint only; the driver app re-reads GET /driver/reservations on it.")
