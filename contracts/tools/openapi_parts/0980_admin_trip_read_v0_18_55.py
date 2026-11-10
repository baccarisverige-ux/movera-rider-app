# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.55 §77 (owner Q34): admin reads of a trip need trips.read + the trip's zone.
_TRIP_READ = ("v0.18.55 §77 (owner Q34): Admin callers need trips.read and the trip's zone in their zones (a Super admin with all zones passes); "
              "otherwise 403 forbidden with reason missing_permission or zone_out_of_scope, the same answers as GET/POST /trips/{tripId}/messages with support.reply. "
              "This applies to both the JSON poll and the SSE stream of /events. Riders and drivers: unchanged (own trip only). x-permission applies to admins only.")
for _p in ("/trips/{tripId}", "/trips/{tripId}/events"):
    _op = PATHS[_p]["get"]
    _op["x-permission"] = "trips.read"
    _op["description"] = (_op.get("description", "") + " " + _TRIP_READ).strip()
