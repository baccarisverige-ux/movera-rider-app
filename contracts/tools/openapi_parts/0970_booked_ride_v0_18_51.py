# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.51 §73 booked waiting and fees.
BR51 = C["bookedRide0_18_51"]
S["Waiting"]["properties"]["waitFrom"] = {"allOf": [ref("Timestamp")], "description": "v0.18.51 §73: " + BR51["waitFrom"]["rule"] + " " + BR51["waitFrom"]["field"]}
for _p in ("/trips/{tripId}/no-show", "/admin/trips/{tripId}/no-show"):
    _op = PATHS[_p]["post"]
    _op["description"] = (_op.get("description", "") + " v0.18.51 §73: " + BR51["noShow"] + " Fee: " + BR51["fees"]["rule"]).strip()
_c = PATHS["/trips/{tripId}/cancel"]["post"]
_c["description"] = (_c.get("description", "") + " v0.18.51 §73 (booked fees): " + BR51["fees"]["rule"]).strip()
_r = PATHS["/admin/trips/{tripId}/reassign"]["post"]
_r["description"] = (_r.get("description", "") + " v0.18.51 §73: " + BR51["l6"]).strip()
