# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.144 (owner 2026-11-20, Rules
# decisions/session-2026-11-06.md; contract.json#liveLocation): the adjust-pickup banner (apps only, reuses
# PATCH pickup and the v0.18.143 route change) and two-way live location sharing. Additive: one route, one SSE frame
# (only with ?live=true), RiderAppConfig.liveLocation.
_LL = C["liveLocation"]
_D = C["configDefaults"]
_V144 = "v0.18.144 (contract.json#liveLocation): "
assert "liveLocation" not in S["RiderAppConfig"]["properties"], "RiderAppConfig.liveLocation exists before v0.18.144"
assert "LiveLocationEvent" not in S, "LiveLocationEvent exists before v0.18.144"
S["RiderAppConfig"]["properties"]["liveLocation"] = obj(OrderedDict([
    ("share", {"type": "boolean", "default": _D["liveLocationShare"]}),
    ("adjustPickupMeters", i("0 = the adjust-pickup banner is off; else 10-500.", minimum=0, maximum=500, default=_D["adjustPickupMeters"])),
    ("sendEverySeconds", i(minimum=5, maximum=10, default=_D["liveLocationSendEverySeconds"])),
]), (), _V144 + _LL["setting"] + " Banner: " + _LL["adjustPickup"]["when"], addl=False)
_POINT = OrderedDict([("lat", n(minimum=-90, maximum=90)), ("lng", n(minimum=-180, maximum=180)), ("accuracyM", n(minimum=0, maximum=5000))])
S["LiveLocationUpdate"] = obj(OrderedDict([("sharing", b())] + list(_POINT.items())), ["sharing"], _V144 + _LL["route"], addl=False)
S["LiveLocationAnswer"] = obj(OrderedDict([("sharing", b()), ("sendEverySeconds", i(minimum=5, maximum=10))]), ["sharing", "sendEverySeconds"], _V144 + _LL["send"], addl=False)
S["LiveLocationEvent"] = obj(OrderedDict([("tripId", ref("Id")), ("side", s(enum=["rider", "driver"])), ("sharing", b())] + list(_POINT.items()) + [("at", ref("Timestamp"))]),
                             ["tripId", "side", "sharing", "at"], _V144 + _LL["relay"] + " " + _LL["privacy"], addl=False)
op("put", "/trips/{tripId}/live-location", "shareLiveLocation", "Share my live location", ["rider", "driver"], "Trips", params=TID,
   body="LiveLocationUpdate", ok=(200, "LiveLocationAnswer"),
   desc=_V144 + _LL["route"] + " " + _LL["window"] + " " + _LL["privacy"] + " " + _LL["driverSide"])
_PUT = PATHS["/trips/{tripId}/live-location"]["put"]
_PUT["responses"]["409"] = {"description": _V144 + "conflict, reason live_location_not_active (outside accept -> pickup) or live_location_off (zone switch off).",
                            "content": {"application/json": {"schema": ref("Error")}}}
_EV = PATHS["/trips/{tripId}/events"]["get"]
_EV["parameters"].insert(3, {"name": "live", "in": "query", "required": False, "schema": {"type": "boolean", "default": False},
                             "description": _V144 + "true: the SSE stream also carries the other side's 'event: live_location' frames (LiveLocationEvent, no id). " + _LL["relay"]})
_EV["description"] = _EV.get("description", "") + " " + _V144 + _LL["relay"]
