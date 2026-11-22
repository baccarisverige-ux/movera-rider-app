# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.145 (S4c load cut, Rules
# audits/impact/stress-s4b-2026-11-20.md "S4c"; contract.json#loadCut): one combined driver Home read, the airport-queue
# hint on the driver config stream, the rider trip-watch fallback and the nearby-cars cache. Additive.
_LC = C["loadCut"]
_V145 = "v0.18.145 (contract.json#loadCut): "
assert "/driver/home-badges" not in PATHS, "/driver/home-badges exists before v0.18.145"
assert "AirportQueueChangedEvent" not in S, "AirportQueueChangedEvent exists before v0.18.145"
S["DriverHomeBadges"] = obj(OrderedDict([
    ("profile", ref("Driver")),
    ("notifications", ref("NotificationPage")),
    ("reminders", ref("DriverReminderList")),
    ("onboardingSettings", nullable("OnboardingSettings")),
]), ["profile", "notifications", "reminders", "onboardingSettings"], _V145 + _LC["homeBadges"])
op("get", "/driver/home-badges", "getDriverHomeBadges", "Home's four badge reads in one", ["driver"], "Driver · Session",
   ok=(200, "DriverHomeBadges"), desc=_V145 + _LC["homeBadges"])
S["AirportQueueChangedEvent"] = obj(OrderedDict([
    ("eventId", ref("Id")), ("kind", s(const="airport_queue_changed")), ("areaId", s()),
    ("occurredAt", ref("Timestamp")), ("serverTime", ref("Timestamp")),
]), ["eventId", "kind", "areaId", "occurredAt", "serverTime"], _V145 + _LC["airportQueueLive"])
for _p in ("/driver/config/stream", "/driver/stream"):
    _g = PATHS[_p]["get"]
    _g["description"] = (_g.get("description", "") + " " + _V145 + "also AirportQueueChangedEvent (kind airport_queue_changed). " + _LC["airportQueueLive"]).strip()
_aq = PATHS["/driver/airport-queue"]["get"]
_aq["description"] += " " + _V145 + _LC["airportQueueLive"] + " Fallback poll: " + str(_LC["airportQueueFallbackSeconds"]) + " s."
_rc = PATHS["/rider/config/stream"]["get"]
_rc["description"] = (_rc.get("description", "") + " " + _V145 + _LC["riderTripWatch"] + " streamUpSeconds = " + str(_LC["riderTripWatchStreamUpSeconds"]) + ".").strip()
_nv = PATHS["/rider/nearby-vehicles"]["get"]
_nv["description"] = (_nv.get("description", "") + " " + _V145 + _LC["nearbyCache"]).strip()
