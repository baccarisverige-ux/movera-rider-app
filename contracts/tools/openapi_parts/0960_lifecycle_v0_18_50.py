# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.50 §72 lifecycle decisions.
LC50 = C["lifecycle0_18_50"]
PATHS["/trips/{tripId}/cancel"]["post"]["description"] = (PATHS["/trips/{tripId}/cancel"]["post"].get("description", "") + " v0.18.50 §72 (L4): " + LC50["l4"]["rule"] + " (L1) The driver of a trip the rider cancels gets driverTripPush rider_cancelled.").strip()
PATHS["/admin/trips/{tripId}/reassign"]["post"]["description"] = (PATHS["/admin/trips/{tripId}/reassign"]["post"].get("description", "") + " v0.18.50 §72 (L6): " + LC50["l6"]["rule"] + " (L1) The driver taken off gets driverTripPush admin_reassigned (a held booked ride: reservation_unassigned).").strip()
