# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.122 (L20 stream; owner
# 2026-11-17 "Yes, with switch (Rec.)", Rules audits/load/l20-1-design.md section 3): GET /driver/stream, the offer feed
# and the driver config stream on one connection (contract.json#driverOneStream), and DriverAppConfig.realtime.oneStream
# (default false). The two old streams and the rider document are unchanged.
_OS = C["driverOneStream"]
assert "/driver/stream" not in PATHS, "/driver/stream exists before v0.18.122"
assert "realtime" not in S["DriverAppConfig"]["properties"], "DriverAppConfig.realtime exists before v0.18.122"
op("get", "/driver/stream", "streamDriverOneStream", "Offer feed + driver config stream on one connection", ["driver"], "Realtime",
   params=[pref("After"), pref("LastEventId")],
   content=sse("Server-sent events: the OfferEvent and ConfigEvent objects of the two old streams, unchanged.", "OfferEvent"),
   desc="v0.18.122 (contract.json#driverOneStream): " + " ".join(_OS[k] for k in ("route", "eventId", "resume", "close", "zone", "server", "driver")))
_p = PATHS["/driver/stream"]["get"]
_p["parameters"] = [{"name": "zoneId", "in": "query", "required": False, "schema": ref("Id"),
                     "description": "As on GET /driver/config/stream (v0.18.72 §89). " + _OS["zone"]}] + _p["parameters"]
S["DriverAppConfig"]["properties"]["realtime"] = obj({"oneStream": {**b(_OS["driver"]), "default": C["configDefaults"]["driverOneStream"]}},
                                                     desc=_OS["note"] + " " + _OS["setting"] + " " + _OS["admin"])
