# v0.18.36 §60 (fix job 9, contract.json#airportQueue): the airport queue.
# A part of tools/gen_openapi.py (rule 25 split, contracts #78), run after 0600 with its globals.
AQ = C["airportQueue"]
AQD = AQ["defaults"]
AQR = AQ["ranges"]
S["AirportQueueArea"] = obj({
    "areaId": ref("Id"),
    "airportZoneId": ref("Id"),
    "polygon": arr(arr(n(), minItems=2, maxItems=2), minItems=3, maxItems=500),
    "on": {**b(), "default": AQD["on"]},
    "leaveGraceMin": {**i(minimum=AQR["leaveGraceMin"][0], maximum=AQR["leaveGraceMin"][1]), "default": AQD["leaveGraceMin"]},
    "offerSeconds": {**i(minimum=AQR["offerSeconds"][0], maximum=AQR["offerSeconds"][1]), "default": AQD["offerSeconds"]},
    "maxQueueOffers": {**i(minimum=AQR["maxQueueOffers"][0], maximum=AQR["maxQueueOffers"][1]), "default": AQD["maxQueueOffers"]},
    "keepPlaceAfterDecline": {**b(AQ["decline"]), "default": AQD["keepPlaceAfterDecline"]},
    "updatedAt": ref("Timestamp"),
}, ["areaId", "airportZoneId", "polygon", "on", "leaveGraceMin", "offerSeconds", "maxQueueOffers", "keepPlaceAfterDecline"], "v0.18.36 §60: " + AQ["area"])
S["AirportQueueAreaUpdate"] = obj({
    "polygon": arr(arr(n(), minItems=2, maxItems=2), minItems=3, maxItems=500),
    "on": b(),
    "leaveGraceMin": i(minimum=AQR["leaveGraceMin"][0], maximum=AQR["leaveGraceMin"][1]),
    "offerSeconds": i(minimum=AQR["offerSeconds"][0], maximum=AQR["offerSeconds"][1]),
    "maxQueueOffers": i(minimum=AQR["maxQueueOffers"][0], maximum=AQR["maxQueueOffers"][1]),
    "keepPlaceAfterDecline": b(),
}, ["polygon", "on"], "v0.18.36 §60: what the admin saves (the whole area); a number left out takes its default.", addl=False)
S["AirportQueueStatus"] = obj({
    "status": s(enum=["in_queue", "not_in_area", "off"]),
    "areaId": ref("Id"),
    "airportZoneId": ref("Id"),
    "position": i("1 = first in line.", minimum=1),
    "ahead": i(minimum=0),
    "joinedAt": ref("Timestamp"),
    "waitingMin": i(minimum=0),
}, ["status"], "v0.18.36 §60: " + AQ["driverRead"] + " " + AQ["leftNotice"])
S["AirportQueueFeedItem"] = obj({
    "areaId": ref("Id"), "airportZoneId": ref("Id"), "on": b(),
    "waiting": i(minimum=0), "longestWaitMin": i(minimum=0), "pickupsLastHour": i(minimum=0),
}, ["areaId", "airportZoneId", "on", "waiting", "longestWaitMin", "pickupsLastHour"])
S["AirportQueueFeed"] = obj({"items": arr(ref("AirportQueueFeedItem"))}, ["items"], "v0.18.36 §60: " + AQ["adminRead"])
op("get", "/driver/airport-queue", "driverAirportQueue", "The driver's own place in the airport queue", ["driver"], "Driver · Session",
   ok=(200, "AirportQueueStatus"), desc="v0.18.36 §60: " + AQ["driverRead"] + " " + AQ["join"] + " " + AQ["leave"])
op("get", "/admin/zones/{zoneId}/queue-area", "adminGetAirportQueueArea", "An airport zone's queue area", ["admin"], "Admin · Zones",
   params=[pref("ZoneId")], ok=(200, "AirportQueueArea"), permission="zones.read", desc="v0.18.36 §60: " + AQ["adminRead"])
op("put", "/admin/zones/{zoneId}/queue-area", "adminPutAirportQueueArea", "Save an airport zone's queue area", ["admin"], "Admin · Zones",
   params=[pref("ZoneId")], body="AirportQueueAreaUpdate", ok=(200, "AirportQueueArea"), mutation=True, permission="zones.edit",
   desc="v0.18.36 §60: only a zone of kind airport (else 400 invalid_request, reason not_airport_zone). Audited. " + AQ["dispatch"] + " " + AQ["serverSafety"])
op("get", "/admin/airport-queues", "adminAirportQueues", "Airport queues for the Dashboard", ["admin"], "Admin · Zones",
   ok=(200, "AirportQueueFeed"), permission="zones.read", desc="v0.18.36 §60: " + AQ["adminRead"])
