# Split from tools/gen_openapi.py (rule 25, no behaviour change): run by it in name order with its globals.
# ---- v0.18.5: deep-fix job of driver groups 1 and 2 (G1-B2/B3/B6/D3, G2-D1..D5.8) + chat storage (G9) + safety (G14)
AU5 = C["auth"]; DO5 = C["driverOnboarding"]; LG = C["legal"]
PATHS["/auth/otp/verify"]["post"]["description"] = PATHS["/auth/otp/verify"]["post"].get("description", "") + " v0.18.5 (G1-B3): " + AU5["signInErrors"]["otp_too_many_attempts"]
PATHS["/auth/refresh"]["post"]["description"] = PATHS["/auth/refresh"]["post"].get("description", "") + " v0.18.5: " + AU5["tokens"]["refreshRetry"] + " " + AU5["signedOut"]["note"] + " Reasons: " + ", ".join(f"{k} = {v}" for k, v in AU5["signedOut"]["reasons"].items()) + "."
# G2-D1 renewal, D5.2 content check, D5.8 expiry limit, D2 owner privacy
S["Document"]["properties"]["renewalOf"] = {"allOf": [ref("Id")], "description": "v0.18.5 (G2-D1): this upload renews that approved document; " + DO5["documentRenewal"]["note"]}
S["DocumentSummary"]["properties"]["renewalOf"] = {"allOf": [ref("Id")], "description": "v0.18.5 (G2-D1): " + DO5["documentRenewal"]["views"]}
PATHS["/driver/documents"]["post"]["description"] = PATHS["/driver/documents"]["post"].get("description", "") + " v0.18.5: " + DO5["documentRenewal"]["note"] + " " + DO5["documents"]["upload"]["contentCheck"] + " " + DO5["documentExpiry"]["maxNote"]
PATHS["/driver/documents/{documentId}/file"]["get"]["description"] = PATHS["/driver/documents/{documentId}/file"]["get"].get("description", "") + " v0.18.5: " + DO5["ownerPrivacy"]["note"]
PATHS["/admin/documents/{documentId}/review"]["post"]["description"] += " v0.18.5: " + DO5["documentExpiry"]["maxNote"] + " " + DO5["reviewReason"] + " Approving a renewal: " + DO5["documentRenewal"]["note"]
S["DriverReminder"]["properties"]["invitationId"] = {"allOf": [ref("Id")], "description": "v0.18.5 (G2-D5.6): fleet_invitation lines."}
S["DriverReminder"]["properties"]["fleetName"] = s("v0.18.5 (G2-D5.6): fleet_invitation lines.")
S["DriverReminder"]["properties"]["renewalStatus"] = s(DO5["reminders"]["renewal"], enum=["in_review", "rejected"])
S["ReminderFix"]["properties"]["invitationId"] = {"allOf": [ref("Id")], "description": "v0.18.5: accept_invitation / decline_invitation."}
PATHS["/driver/fleet/invite"]["post"]["description"] += " v0.18.5: " + DO5["fleetInvitations"]["privacy"]
S["FleetInvitation"]["properties"]["driverName"] = s("v0.18.5 (G2-D5.5): never in the owner's view of an owner_invite before it is accepted. " + DO5["fleetInvitations"]["privacy"])
# G2-D5.3 categories by the admin
S["VehicleRequest"]["properties"]["categoryIds"] = arr(ref("CategoryId"), description="Deprecated v0.18.5 (G2-D5.3): ignored, never stored. " + DO5["vehicleRules"]["categoriesByAdmin"], deprecated=True)
S["VehicleReviewCommand"]["properties"]["categoryIds"] = arr(ref("CategoryId"), uniqueItems=True, description="v0.18.5 (G2-D5.3): the categories the admin gives on approval. " + DO5["vehicleRules"]["categoriesByAdmin"])
S["VehicleReviewCommand"]["properties"]["note"]["description"] = DO5["reviewReason"]
S["Vehicle"]["properties"]["fitCategories"] = arr(ref("CategoryId"), description=DO5["vehicleRules"]["fitCategories"])
PATHS["/admin/vehicles/{vehicleId}/review"]["post"]["description"] = PATHS["/admin/vehicles/{vehicleId}/review"]["post"].get("description", "") + " v0.18.5: " + DO5["vehicleRules"]["categoriesByAdmin"] + " " + DO5["reviewReason"]
PATHS["/driver/vehicles"]["post"]["description"] = PATHS["/driver/vehicles"]["post"].get("description", "") + " v0.18.5: " + DO5["vehicleRules"]["categoriesByAdmin"]
S["DocumentReviewCommand"]["properties"]["note"]["description"] = DO5["reviewReason"]
# G2-D3 the driver's approved photo
S["DriverSummary"]["properties"]["photoUrl"] = s("v0.18.5 (G2-D3): " + DO5["riderDriverPhoto"]["url"], format="uri-reference")
op("get", "/rider/trips/{tripId}/driver-photo", "riderDriverPhoto", "The driver's approved profile photo (trip's rider, while the driver comes and during the trip)", ["rider"], "Rider · Trip",
   params=TID, content={mt: {"schema": {"type": "string", "format": "binary"}} for mt in ["image/jpeg", "image/png", "image/heic"]}, desc="v0.18.5: " + DO5["riderDriverPhoto"]["endpoint"])
# G2-D4 notices
S["Notification"]["description"] += " v0.18.5 (G2-D4): " + DO5["fleetLeaveNotices"]["note"] + " data " + DO5["fleetLeaveNotices"]["data"] + ". v0.18.5 (G9): " + C["chat"]["appStorage"]["noBellNotice"]
# G9 chat after the trip
S["MessagePage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("Message")),
                    "closed": b("v0.18.5 (G9): true for the rider and the driver once the trip is terminal; items is then empty.")}}], "description": "Page<Message>"}
PATHS["/trips/{tripId}/messages"]["get"]["description"] += " v0.18.5 (G9): " + C["chat"]["appStorage"]["afterTrip"] + " " + C["chat"]["appStorage"]["admin"]
# G14
for _sos in ("/rider/trips/{tripId}/sos", "/driver/trips/{tripId}/sos"):
    PATHS[_sos]["post"]["description"] = PATHS[_sos]["post"].get("description", "") + " v0.18.5: " + C["safety"]["onlyDuringTrip"]["note"] + " " + C["safety"]["onlyDuringTrip"]["server"]
# G1-B2 legal texts per country
LANG3 = obj({"sv": s(minLength=1, maxLength=200), "fr": s(minLength=1, maxLength=200), "en": s(minLength=1, maxLength=200)}, ["sv", "fr", "en"])
LTEXT = obj({"sv": s(minLength=1, maxLength=20000), "fr": s(minLength=1, maxLength=20000), "en": s(minLength=1, maxLength=20000)}, ["sv", "fr", "en"])
S["LegalDocument"] = obj({"title": LANG3, "text": LTEXT}, ["title", "text"], "v0.18.5: one legal text (terms or privacy) in sv / fr / en.")
S["LegalCompany"] = obj({"companyName": s(maxLength=200), "orgNumber": s(maxLength=60), "address": s(maxLength=300), "supportEmail": s(format="email", maxLength=200),
                         "supportPhone": s(pattern=r"^\+[1-9]\d{6,14}$")}, [], "v0.18.5: " + LG["company"])
S["LegalCountry"] = s(enum=LG["countries"])
S["LegalTexts"] = obj({"country": ref("LegalCountry"), "version": i(minimum=0), "source": s(enum=["default", "admin"]), "publishedAt": ref("Timestamp"),
                       "reaccept": b(), "reacceptFrom": {"type": ["integer", "null"], "minimum": 1, "description": "The newest version published with reaccept (null: none); a person must have accepted it or a later version (contract.json#legal.accept)."},
                       "terms": ref("LegalDocument"), "privacy": ref("LegalDocument")},
                      ["country", "version", "source", "reaccept", "terms", "privacy"], "v0.18.5: " + LG["read"])
S["LegalVersion"] = obj({"country": ref("LegalCountry"), "version": i(minimum=0), "source": s(enum=["default", "admin"]), "publishedAt": ref("Timestamp"), "publishedBy": ref("Id"),
                         "reaccept": b(), "terms": ref("LegalDocument"), "privacy": ref("LegalDocument"), "company": ref("LegalCompany")},
                        ["country", "version", "source", "reaccept", "terms", "privacy", "company"], "v0.18.5: the raw texts with their placeholders.")
S["LegalAdminView"] = obj({"live": ref("LegalVersion"), "history": arr(ref("LegalVersion"))}, ["live", "history"], "v0.18.5: " + LG["admin"])
S["LegalPublishCommand"] = obj({"terms": ref("LegalDocument"), "privacy": ref("LegalDocument"), "company": ref("LegalCompany"), "reaccept": b()}, ["terms", "privacy"], "v0.18.5: " + LG["admin"])
S["LegalAcceptCommand"] = obj({"country": ref("LegalCountry"), "version": i(minimum=1)}, ["country", "version"], "v0.18.5: " + LG["accept"])
PARAMS["LegalCountryPath"] = {"name": "country", "in": "path", "required": True, "schema": ref("LegalCountry")}
o = op("get", "/legal/{country}", "getLegalTexts", "Terms of use and privacy policy of a country (no token)", ["rider", "driver"], "Account", params=[pref("LegalCountryPath")], ok=(200, "LegalTexts"),
       desc="v0.18.5: " + LG["note"] + " " + LG["read"] + " " + LG["apps"] + " " + LG["lawyerReview"])
o["security"] = []
op("get", "/admin/legal/{country}", "adminGetLegal", "The live legal texts of a country and their history", ["admin"], "Admin · Config", params=[pref("LegalCountryPath")], ok=(200, "LegalAdminView"), permission="settings.read", desc="v0.18.5: " + LG["admin"])
op("post", "/admin/legal/{country}/publish", "adminPublishLegal", "Publish new legal texts for a country", ["admin"], "Admin · Config", params=[pref("LegalCountryPath")], body="LegalPublishCommand", ok=(200, "LegalVersion"), mutation=True, permission="settings.publish", desc="v0.18.5: " + LG["admin"] + " " + LG["company"])
op("post", "/account/legal/accept", "acceptLegal", "Accept the live legal texts of a country", ["rider", "driver"], "Account", body="LegalAcceptCommand", ok=(204, None), mutation=True, desc="v0.18.5: " + LG["accept"])


# ---------------------------------------------------------------- v0.18.6: driver group 4 Dispatch tools (G4-F1..F6) and offline reason
DT = C["dispatchTools"]
SO6 = C["driverHome"]["setOffline"]
S["Driver"]["properties"].update({
    "offlineReason": s("v0.18.6 (owner 'Send the real reason'): why the server set the driver offline; only while onlineStatus is offline, cleared on going online. " + SO6["offlineReason"], enum=SO6["offlineReasons"]),
    "offlineNote": s("v0.18.6: with offlineReason vehicle_blocked, the admin's note.", maxLength=1000),
    "offlineAt": ref("Timestamp"),
})
for nm in ["presetId", "groupId", "radarZoneId", "ruleId", "eventId"]:
    PARAMS[nm[0].upper() + nm[1:]] = path_id(nm)
PARAMS["CountryQuery"] = {"name": "country", "in": "query", "required": False, "description": "v0.18.6: one country (SE, FR); without it every country in the admin's scope.", "schema": ref("CountryCode")}
PARAMS["ExpectedVersionQuery"] = {"name": "expectedVersion", "in": "query", "required": True, "schema": {"type": "integer", "minimum": 1}}
NAME40 = s(minLength=1, maxLength=40)
AUD = {"version": i(minimum=1), "createdBy": ref("Id"), "createdAt": ref("Timestamp"), "updatedBy": ref("Id"), "updatedAt": ref("Timestamp")}
S["DispatchPresetValues"] = {"type": "object", "description": "v0.18.6 (F2): a DispatchDocument without version, publishedAt, zoneId, country, timeZone, usesStandard.", "additionalProperties": True}
S["DispatchPreset"] = obj(dict({"presetId": ref("Id"), "country": ref("CountryCode"), "name": NAME40, "values": ref("DispatchPresetValues")}, **AUD),
                          ["presetId", "country", "name", "values", "version", "createdAt"], "v0.18.6: " + DT["presets"]["note"])
S["DispatchPresetCreate"] = obj({"country": ref("CountryCode"), "name": NAME40, "values": ref("DispatchPresetValues")}, ["country", "name", "values"])
S["DispatchPresetUpdate"] = obj({"expectedVersion": i(minimum=1), "name": NAME40, "values": ref("DispatchPresetValues")}, ["expectedVersion"])
S["DispatchPresetList"] = obj({"items": arr(ref("DispatchPreset"))}, ["items"])
S["DriverGroup"] = obj(dict({"groupId": ref("Id"), "country": ref("CountryCode"), "name": NAME40, "driverIds": arr(ref("Id"), maxItems=DT["groups"]["maxDrivers"], uniqueItems=True)}, **AUD),
                       ["groupId", "country", "name", "driverIds", "version", "createdAt"], "v0.18.6: " + DT["groups"]["note"])
S["DriverGroupCreate"] = obj({"country": ref("CountryCode"), "name": NAME40, "driverIds": arr(ref("Id"), maxItems=DT["groups"]["maxDrivers"], uniqueItems=True)}, ["country", "name", "driverIds"])
S["DriverGroupUpdate"] = obj({"expectedVersion": i(minimum=1), "name": NAME40, "driverIds": arr(ref("Id"), maxItems=DT["groups"]["maxDrivers"], uniqueItems=True)}, ["expectedVersion"])
S["DriverGroupList"] = obj({"items": arr(ref("DriverGroup"))}, ["items"])
S["RadarZone"] = obj(dict({"radarZoneId": ref("Id"), "country": ref("CountryCode"), "zoneId": ref("Id"), "name": NAME40, "polygon": ref("ZonePolygon")}, **AUD),
                     ["radarZoneId", "country", "zoneId", "name", "polygon", "version", "createdAt"], "v0.18.6: " + DT["radarZones"]["note"])
S["RadarZoneCreate"] = obj({"zoneId": ref("Id"), "name": NAME40, "polygon": ref("ZonePolygon")}, ["zoneId", "name", "polygon"], "The country is the zone's.")
S["RadarZoneUpdate"] = obj({"expectedVersion": i(minimum=1), "name": NAME40, "polygon": ref("ZonePolygon")}, ["expectedVersion"])
S["RadarZoneList"] = obj({"items": arr(ref("RadarZone"))}, ["items"])
RZR = DT["radarZones"]["ranges"]
RULE = {"name": NAME40, "radarZoneIds": {"oneOf": [s(const="all"), arr(ref("Id"), minItems=1, uniqueItems=True)]},
        "seconds": i(minimum=RZR["seconds"][0], maximum=RZR["seconds"][1]), "maxDrivers": i(minimum=RZR["maxDrivers"][0], maximum=RZR["maxDrivers"][1]), "repeat": b("Send again by itself until taken (F4).")}
S["RadarZoneRule"] = obj(dict({"ruleId": ref("Id"), "country": ref("CountryCode")}, **RULE, **AUD),
                         ["ruleId", "country", "name", "radarZoneIds", "seconds", "maxDrivers", "repeat", "version", "createdAt"], "v0.18.6 (F4)")
S["RadarZoneRuleCreate"] = obj(dict({"country": ref("CountryCode")}, **RULE), ["country", "name", "radarZoneIds", "seconds", "maxDrivers", "repeat"])
S["RadarZoneRuleUpdate"] = obj(dict({"expectedVersion": i(minimum=1)}, **RULE), ["expectedVersion"])
S["RadarZoneRuleList"] = obj({"items": arr(ref("RadarZoneRule"))}, ["items"])
S["RadarZoneSend"] = obj({"sendId": ref("Id"), "tripId": ref("Id"), "radarZoneId": ref("Id"), "ruleId": ref("Id"), "seconds": i(), "intervalSeconds": i("Same as seconds: the time between rounds."), "maxDrivers": i(), "repeat": b(), "active": b(),
                          "rounds": i(minimum=1), "startedAt": ref("Timestamp"), "stoppedAt": ref("Timestamp"),
                          "stopReason": s(enum=["admin", "accepted", "search_ended", "trip_over", "replaced"])},
                         ["sendId", "tripId", "radarZoneId", "ruleId", "seconds", "intervalSeconds", "maxDrivers", "repeat", "active", "rounds", "startedAt"], "v0.18.6 (F4): " + DT["radarZones"]["sendView"])
S["TripProjection"]["properties"]["radarZoneSend"] = {"allOf": [ref("RadarZoneSend")], "description": "v0.18.6 (G4-F4), admin view of GET /admin/trips/{tripId} only: the trip's repeating radar-zone send while it is active; absent once a driver accepted, an admin stopped it, the search ended or the trip ended."}
S["RadarZoneFree"] = obj({"radarZoneId": ref("Id"), "free": i(minimum=0), "at": ref("Timestamp")}, ["radarZoneId", "free", "at"], "v0.18.6 (F4): free drivers inside the radar zone now.")
S["RadarZoneStopCommand"] = obj({"note": s(maxLength=1000)})
S["LocalizedText"] = obj({"sv": s(minLength=1), "fr": s(minLength=1), "en": s(minLength=1)}, ["sv", "fr", "en"])
S["EventDetails"] = obj({"title": ref("LocalizedText"), "description": ref("LocalizedText"), "pickupNote": ref("LocalizedText")}, ["title", "description"],
                        "title ≤ 80, description ≤ 1000, pickupNote ≤ 300 characters per language.")
S["LatLngPoint"] = obj({"lat": n(minimum=-90, maximum=90), "lng": n(minimum=-180, maximum=180)}, ["lat", "lng"])
EVF = {"name": s(minLength=1, maxLength=80), "location": ref("LatLngPoint"), "polygon": ref("ZonePolygon"), "startsAt": ref("Timestamp"), "endsAt": ref("Timestamp"), "on": b(), "details": ref("EventDetails")}
S["DispatchEvent"] = obj(dict({"eventId": ref("Id"), "country": ref("CountryCode")}, **EVF, **AUD),
                         ["eventId", "country", "name", "location", "startsAt", "endsAt", "on", "details", "version", "createdAt"], "v0.18.6: " + DT["events"]["note"])
S["DispatchEventCreate"] = obj(dict({"country": ref("CountryCode")}, **EVF), ["country", "name", "location", "startsAt", "endsAt", "details"], "on defaults to true.")
S["DispatchEventUpdate"] = obj(dict({"expectedVersion": i(minimum=1)}, **EVF), ["expectedVersion"])
S["DispatchEventList"] = obj({"items": arr(ref("DispatchEvent"))}, ["items"])
S["DriverEvent"] = obj({"eventId": ref("Id"), "name": s(), "location": ref("LatLngPoint"), "polygon": ref("ZonePolygon"), "startsAt": ref("Timestamp"), "endsAt": ref("Timestamp"),
                        "running": b(), "title": s(), "description": s(), "pickupNote": s(), "language": ref("Language")},
                       ["eventId", "name", "location", "startsAt", "endsAt", "running", "title", "description", "language"], "v0.18.6 (F6): " + DT["events"]["driverEntity"])
S["DriverEventList"] = obj({"items": arr(ref("DriverEvent")), "at": ref("Timestamp")}, ["items", "at"])
S["AdminRadarGroupCommand"]["required"] = ["expectedVersion"]
S["AdminRadarGroupCommand"]["properties"].update({"groupId": ref("Id"), "radarZoneId": ref("Id"), "ruleId": ref("Id")})
S["AdminRadarGroupCommand"]["description"] += " " + C["adminDispatch"]["radarGroup"]["v0186"]
S["AdminRadarGroup"]["properties"].update({"pickedFrom": s(enum=["drivers", "group", "radar_zone"]), "radarZoneSend": ref("RadarZoneSend")})
ADM = "Admin · Dispatch"
def crud(base, idp, ent, plural, label, audit):
    op("get", f"/admin/dispatch/{base}", f"adminList{plural}", f"{label}s per country", ["admin"], ADM, params=[pref("CountryQuery")], ok=(200, f"{ent}List"), permission=DT["permissions"]["read"])
    op("post", f"/admin/dispatch/{base}", f"adminCreate{ent}", f"Create a {label.lower()}", ["admin"], ADM, body=f"{ent}Create", ok=(201, ent), mutation=True, permission=DT["permissions"]["write"],
       desc=f"v0.18.6. Audited ({audit}.create). 409 name_taken.")
    op("put", f"/admin/dispatch/{base}/{{{idp}}}", f"adminUpdate{ent}", f"Change a {label.lower()}", ["admin"], ADM, params=[pref(idp[0].upper() + idp[1:])], body=f"{ent}Update", ok=(200, ent), mutation=True,
       permission=DT["permissions"]["write"], desc=f"v0.18.6. Audited ({audit}.update). 409 version_mismatch / name_taken.")
    op("delete", f"/admin/dispatch/{base}/{{{idp}}}", f"adminDelete{ent}", f"Delete a {label.lower()}", ["admin"], ADM, params=[pref(idp[0].upper() + idp[1:]), pref("ExpectedVersionQuery")], ok=(204, None), mutation=True,
       permission=DT["permissions"]["write"], desc=f"v0.18.6. Audited ({audit}.delete).")
crud("presets", "presetId", "DispatchPreset", "DispatchPresets", "Dispatch preset", "dispatch.preset")
crud("groups", "groupId", "DriverGroup", "DriverGroups", "Driver group", "dispatch.group")
crud("radar-zones", "radarZoneId", "RadarZone", "RadarZones", "Radar zone", "dispatch.radar_zone")
crud("radar-rules", "ruleId", "RadarZoneRule", "RadarZoneRules", "Radar zone rule", "dispatch.radar_rule")
crud("events", "eventId", "DispatchEvent", "DispatchEvents", "Event", "dispatch.event")
op("get", "/admin/dispatch/radar-zones/{radarZoneId}/free", "adminRadarZoneFree", "Free drivers inside a radar zone now", ["admin"], ADM,
   params=[pref("RadarZoneId"), q("categoryId", ref("CategoryId"))], ok=(200, "RadarZoneFree"), permission=DT["permissions"]["read"])
op("post", "/admin/trips/{tripId}/radar-zone/stop", "adminStopRadarZone", "Stop the repeating radar-zone send of a trip", ["admin"], ADM,
   params=TID, body="RadarZoneStopCommand", ok=(200, "RadarZoneSend"), mutation=True, permission=DT["permissions"]["send"],
   desc="v0.18.6 (F4). Audited (trip.radar_zone_stop). 404 radar_zone_send_not_found when none runs.")
op("get", "/driver/events", "listDriverEvents", "Events on the driver's map (running and upcoming)", ["driver"], "Driver · Home", ok=(200, "DriverEventList"),
   desc="v0.18.6 (F6): " + DT["events"]["note"])


# ---- v0.18.7 (driver group 5: going to pickup, waiting items shared with group 6; contract.json#pickupWaiting)
PW = C["pickupWaiting"]
S["RiderWaiting"]["properties"]["cancelAfterArrivedIsNoShow"] = b("v0.18.7 (Q2): " + PW["servedConfig"]["cancelAfterArrivedIsNoShow"]["note"] + " Default " + str(PW["servedConfig"]["cancelAfterArrivedIsNoShow"]["default"]).lower() + ".")
S["RiderAppConfig"]["properties"]["booking"]["properties"]["maxPickupMoveMeters"]["description"] += " v0.18.7: default 200, range 0–2000 (contract.json#pickupWaiting.pickupMove); the server checks it on PATCH /trips/{tripId}."
S["DriverAppConfig"]["properties"]["booking"]["properties"]["maxPickupMoveMeters"]["description"] += " v0.18.7: default 200, range 0–2000 (contract.json#pickupWaiting.pickupMove); the server checks it on PATCH /trips/{tripId}."
for _cfg in ("RiderAppConfig", "DriverAppConfig"):
    S[_cfg]["properties"]["booking"]["properties"]["samePointWarnMeters"] = i("v0.18.30 (owner Q9, contract.json#smallFixes.samePoint): pickup ≈ drop-off warning under this many metres (straight line, no stops); a warning only, the rider can still book. Default 100, 0 = never warn. Admin Dispatch › Rides 'Shortest ride (m)'.", minimum=0, maximum=1000)
S["RiderSummary"] = obj({"firstName": s(minLength=1), "rating": n("The rider's average (2 decimals); only while DriverAppConfig.offers.offerCard.riderRating is on and the rider has one.", minimum=0, maximum=5)},
                        ["firstName"], "v0.18.7 (Q1): " + PW["riderSummary"]["note"])
S["TripTerms"] = obj(OrderedDict([
    ("currency", ref("CurrencyCode")),
    ("freeWaitMin", n(PW["terms"]["fields"]["freeWaitMin"], minimum=0)),
    ("waitPerMin", {"allOf": [ref("Money")], "description": PW["terms"]["fields"]["waitPerMin"]}),
    ("noShowAfterMin", n(PW["terms"]["fields"]["noShowAfterMin"], minimum=0)),
    ("noShowFee", {"allOf": [ref("Money")], "description": PW["terms"]["fields"]["noShowFee"]}),
    ("noShowDriverSharePct", n(PW["terms"]["fields"]["noShowDriverSharePct"], minimum=0, maximum=100)),
    ("cancelRule", {"description": PW["terms"]["fields"]["cancelRule"], **nullable("FeeRule")}),
    ("cancelDriverSharePct", n(PW["terms"]["fields"]["cancelDriverSharePct"], minimum=0, maximum=100)),
    ("cancelAfterArrivedIsNoShow", b(PW["terms"]["fields"]["cancelAfterArrivedIsNoShow"])),
    ("maxPickupMoveMeters", i(PW["terms"]["fields"]["maxPickupMoveMeters"], minimum=0)),
]), ["currency", "freeWaitMin", "waitPerMin", "noShowAfterMin", "noShowFee", "cancelRule", "cancelAfterArrivedIsNoShow", "maxPickupMoveMeters"],
    "v0.18.7: " + PW["terms"]["note"])
S["TripEta"] = obj(OrderedDict([
    ("etaSeconds", i(PW["eta"]["fields"]["etaSeconds"], minimum=60)),
    ("distanceMeters", i(PW["eta"]["fields"]["distanceMeters"], minimum=0)),
    ("target", s(enum=["pickup", "dropoff"])),
    ("at", ref("Timestamp")),
    ("source", s(PW["eta"]["fields"]["source"], enum=["osrm", "estimate", "stale"])),
]), ["etaSeconds", "distanceMeters", "target", "at", "source"], "v0.18.7 (Q4): " + PW["eta"]["note"])
S["TripProjection"]["properties"]["rider"] = {"allOf": [ref("RiderSummary")], "description": "v0.18.7 (Q1): driver and admin views only, from accept to the end; never in the rider's own view."}
S["TripProjection"]["properties"]["terms"] = {"allOf": [ref("TripTerms")], "description": "v0.18.7: the rules this trip is charged by, from booking to the end (all views). " + PW["terms"]["riderView"]}
S["TripProjection"]["properties"]["eta"] = {"allOf": [ref("TripEta")], "description": "v0.18.7 (Q4): the server's road-route ETA, refreshed every " + str(PW["eta"]["everySeconds"]) + " s while a driver is on the way or driving (all views). etaSeconds repeats eta.etaSeconds for older builds."}
S["Waiting"]["properties"].update({
    "noShowFee": {"allOf": [ref("Money")], "description": "v0.18.7 (Q6): the no-show fee of this trip (terms.noShowFee), set at arrive."},
    "noShowDriverShare": {"allOf": [ref("Money")], "description": "v0.18.7 (Q6): what the driver gets of it (noShowDriverSharePct), for the no-show confirm."},
    "chargedSecondsNow": i("v0.18.7 (Q5): while status is arrived, the paid seconds so far at read time (no version change).", minimum=0),
    "chargedSoFar": {"allOf": [ref("Money")], "description": "v0.18.7 (Q5): while status is arrived, the waiting cost so far at read time (chargedSecondsNow × waitPerMin per minute)."},
})
S["Cancellation"]["properties"].update({
    "feeKind": s("v0.18.7 (Q2): " + PW["cancelAfterArrived"]["cancellationFields"]["feeKind"], enum=["cancel", "no_show"]),
    "driverShare": {"allOf": [ref("Money")], "description": "v0.18.7 (Q6): " + PW["cancelAfterArrived"]["cancellationFields"]["driverShare"]},
})
S["Rider"]["properties"]["wallets"] = arr(ref("Money"), description="v0.18.28 (admin rider view only, contract.json#walletCurrency.admin): every non-zero wallet balance, one per currency.")
S["Rider"]["properties"]["outstandingByCurrency"] = arr(ref("Money"), description="v0.18.7 (Q3): " + PW["debtByCurrency"]["riderView"])
S["Rider"]["properties"]["outstanding"]["description"] += " v0.18.7: the owed fees in the rider's oldest owed currency (contract.json#pickupWaiting.debtByCurrency)."
S["RealtimeEvent"]["properties"]["eta"] = {"allOf": [ref("TripEta")], "description": "v0.18.7: on a kind=location event sent by the ETA tick (every " + str(PW["eta"]["everySeconds"]) + " s)."}
PATHS["/trips/{tripId}"]["patch"]["description"] = PATHS["/trips/{tripId}"]["patch"].get("description", "") + " v0.18.7 (contract.json#pickupWaiting.pickupMove): " + PW["pickupMove"]["note"]
PATHS["/trips/{tripId}"]["patch"]["summary"] = "Move the pickup (v0.18.7); route / payment change later"
PATHS["/trips/{tripId}"]["get"]["description"] = PATHS["/trips/{tripId}"]["get"].get("description", "") + " v0.18.7 (contract.json#pickupWaiting.follow): the apps follow the trip on its stream and poll this only while the stream is down, every " + str(PW["follow"]["pollSeconds"]) + " s (never under " + str(PW["follow"]["minPollSeconds"]) + ")."
PATHS["/trips/{tripId}/cancel"]["post"]["description"] += " v0.18.7 (Q2, contract.json#pickupWaiting.cancelAfterArrived): " + PW["cancelAfterArrived"]["note"]
PATHS["/trips/{tripId}/arrive"]["post"]["description"] = PATHS["/trips/{tripId}/arrive"]["post"].get("description", "") + " v0.18.7 (Q6): waiting.noShowFee and waiting.noShowDriverShare are set here."
PATHS["/quotes"]["post"]["description"] = PATHS["/quotes"]["post"].get("description", "") + " v0.18.7 (Q3, contract.json#pickupWaiting.debtByCurrency): " + PW["debtByCurrency"]["note"]
for _p in ["/rider/config", "/driver/config"]:
    PATHS[_p]["get"]["description"] = PATHS[_p]["get"].get("description", "") + " v0.18.7 (contract.json#pickupWaiting.servedConfig): " + PW["servedConfig"]["note"]
PATHS["/admin/trips"]["get"]["description"] = PATHS["/admin/trips"]["get"].get("description", "") + " v0.18.7: " + PW["adminLiveRow"]["note"]
PATHS["/rider/profile"]["get"]["description"] = PATHS["/rider/profile"]["get"].get("description", "") + " v0.18.7 (Q3): " + PW["debtByCurrency"]["riderView"]



# ---- v0.18.8 (driver group 6: arrived and waiting; contract.json#arrivedWaiting)
AW = C["arrivedWaiting"]
_AWR = AW["rules"]
S["WaitingRuleOverride"] = obj(OrderedDict([
    ("on", b("The rule is used (default true).")),
    ("freeWaitMin", {"type": ["number", "null"], "minimum": 0, "description": "null = keep."}),
    ("perMin", {"description": "null = keep; Money in the zone's currency.", **nullable("Money")}),
    ("noShowAfterMin", {"type": ["number", "null"], "minimum": 0, "description": "null = follows freeWaitMin when this rule sets it, else keep."}),
    ("noShowFee", {"description": "null = keep; Money in the zone's currency.", **nullable("Money")}),
]), desc="v0.18.8: " + _AWR["source"])
S["FarPickupWaiting"] = {"allOf": [ref("WaitingRuleOverride"), obj({"km": n("Pickups strictly farther than this (driver's distance at accept) get the rule (default 5).", minimum=0)})], "description": "v0.18.8: " + _AWR["match"]["far_pickup"]}
S["EventWaiting"] = {"allOf": [ref("WaitingRuleOverride"), obj({"radiusMeters": i("Event without a polygon: pickups within this distance of its location (default 500).", minimum=0),
                                                                 "afterEndMin": i("Minutes after endsAt the rule still applies (default 0).", minimum=0)})], "description": "v0.18.8: " + _AWR["match"]["event"]}
S["DriverWaiting"]["allOf"].append(obj(OrderedDict([
    ("farPickup", ref("FarPickupWaiting")),
    ("rideTypes", obj({"scheduled": {"allOf": [ref("WaitingRuleOverride")], "description": "v0.18.8: " + _AWR["match"]["scheduled"] + "; freeWaitMin = the reservation policy's included waiting."},
                       "airport": {"allOf": [ref("WaitingRuleOverride")], "description": "v0.18.8: " + _AWR["match"]["airport"]},
                       "event": ref("EventWaiting")})),
    ("stopFreeWaitMin", n("v0.18.8: " + _AWR["stops"], minimum=0)),
]), desc="v0.18.8 (contract.json#arrivedWaiting.rules): " + _AWR["order"]))
for _k in ("farPickup", "rideTypes", "stopFreeWaitMin"):
    S["RiderWaiting"]["properties"][_k] = {"description": "v0.18.8: copied from the zone's driver document when served (GET /rider/config)."}
S["PickupPinSettings"] = obj(OrderedDict([
    ("required", {**b("Rider PIN before Start in this zone."), "default": False}),
    ("maxAttempts", {**i("Wrong tries in a row before the lock.", minimum=1, maximum=10), "default": 5}),
    ("lockMinutes", {**i("Lock after maxAttempts wrong tries.", minimum=1, maximum=60), "default": 5}),
]), desc="v0.18.8: " + AW["pin"]["switch"] + " " + AW["pin"]["compat"])
S["DriverAppConfig"]["properties"]["pickupPin"] = ref("PickupPinSettings")
S["WaitingAlert"] = obj({"kind": s(enum=AW["alerts"]["kinds"]), "at": ref("Timestamp")}, ["kind", "at"], "v0.18.8: " + AW["alerts"]["note"])
S["Waiting"]["properties"].update({
    "rules": arr(s(enum=_AWR["ruleIds"]), description="v0.18.8: the applied waiting rules (set at arrive; [] = the category's own terms). " + _AWR["order"]),
    "freeWaitMin": n("v0.18.8: the effective free waiting minutes (set at arrive).", minimum=0),
    "perMin": {"allOf": [ref("Money")], "description": "v0.18.8: the effective waiting price per minute (set at arrive)."},
    "noShowAfterMin": n("v0.18.8: the effective no-show minutes (set at arrive).", minimum=0),
    "paidMinutes": i("v0.18.8: " + _AWR["projection"]["waiting"], minimum=0),
    "alerts": arr(ref("WaitingAlert"), description="v0.18.8: island messages sent so far (contract.json#arrivedWaiting.alerts)."),
})
S["TripTerms"]["properties"]["waitingRules"] = arr(s(enum=_AWR["ruleIds"]), description="v0.18.8: " + _AWR["projection"]["terms"])
S["TripTerms"]["properties"]["stopFreeWaitMin"] = n("v0.18.8: free minutes at each middle stop (0 = none).", minimum=0)
S["Cancellation"]["properties"]["reversal"] = obj({"at": ref("Timestamp"), "by": ref("Id"), "reason": s(maxLength=1000), "driverShareTakenBack": b()}, ["at", "by", "reason", "driverShareTakenBack"],
                                                   "v0.18.8 (admin view; rider and driver see it without reason and by): " + AW["reverseNoShow"]["effect"])
S["Cancellation"]["properties"]["refundedAt"] = {"allOf": [ref("Timestamp")], "description": "v0.18.8: a reversed no-show whose fee was already paid: when it went back to the wallet (feeStatus stays waived)."}
S["Cancellation"]["properties"]["refundedToWallet"] = b("v0.18.8: the paid fee went back to the rider's wallet (reverse no-show).")
S["TripProjection"]["properties"]["pickupPin"] = s("v0.18.8: rider and admin views only. " + AW["pin"]["code"], pattern=r"^\d{4}$")
S["TripProjection"]["properties"]["pinVerified"] = b("v0.18.8: the driver gave the right PIN (only with pinRequired).")
S["TripProjection"]["properties"]["pinAttempts"] = i("v0.18.8: admin view only, wrong PIN tries in a row.", minimum=0)
S["TripProjection"]["properties"]["pinBlocked"] = b("v0.18.8: admin view only, the PIN is blocked after 3 × maxAttempts wrong tries until an admin unlocks it.")
S["PinVerification"]["properties"]["version"] = i("v0.18.8: the trip's version after the right PIN (version + 1).", minimum=1)
S["BoardCommand"]["allOf"][1]["properties"]["verifiedPinToken"]["description"] = "Informative since v0.18.8: the verification is kept on the trip; send { pin } or verify first."
S["BoardCommand"]["allOf"][1]["properties"]["verifiedPinToken"]["deprecated"] = True
S["BoardCommand"]["allOf"][1]["properties"]["pin"] = s("v0.18.8: the rider's 4-digit PIN (instead of verifiedPinToken). " + AW["pin"]["check"], pattern=r"^\d{4}$", writeOnly=True)
S["StartTripCommand"] = {"allOf": [ref("TripCommand"), obj({"pin": s("v0.18.8: the rider's 4-digit PIN when the trip needs one and it was not given yet.", pattern=r"^\d{4}$", writeOnly=True)})]}
PATHS["/trips/{tripId}/start"]["post"]["requestBody"]["content"]["application/json"]["schema"] = ref("StartTripCommand")
PATHS["/trips/{tripId}/pin/verify"]["post"]["description"] = "v0.18.8: " + AW["pin"]["check"]
PATHS["/trips/{tripId}/pin"]["get"]["description"] = "v0.18.8: " + AW["pin"]["code"]
PATHS["/trips/{tripId}/arrive"]["post"]["description"] += " v0.18.8: " + _AWR["appliedAt"]
S["AdminReverseNoShowCommand"] = obj(dict(EV, reason=s(minLength=1, maxLength=1000), takeBackDriverShare={**b("Take back the driver's share of the no-show fee (default false, owner decision 34)."), "default": False}),
                                     ["expectedVersion", "reason"], "v0.18.8: " + AW["reverseNoShow"]["note"])
op("post", "/admin/trips/{tripId}/reverse-no-show", "adminReverseNoShow", "Reverse a no-show (reason required, driver share kept unless taken back)", ["admin"], "Admin · Trips",
   params=TID, body="AdminReverseNoShowCommand", ok=(200, TP), mutation=True, permission="trips.intervene", permission_v050="trips.edit",
   desc="v0.18.8: " + AW["reverseNoShow"]["note"] + " " + AW["reverseNoShow"]["effect"] + " " + AW["reverseNoShow"]["idempotent"])
S["AdminPinUnlockCommand"] = obj(dict(EV, reason=s(minLength=1, maxLength=1000)), ["expectedVersion", "reason"], "v0.18.8: " + AW["pin"]["admin"])
op("post", "/admin/trips/{tripId}/pin/unlock", "adminUnlockTripPin", "Unlock a blocked or locked rider PIN", ["admin"], "Admin · Trips",
   params=TID, body="AdminPinUnlockCommand", ok=(200, TP), mutation=True, permission="trips.intervene", permission_v050="trips.edit", desc="v0.18.8: " + AW["pin"]["admin"])
for _p in ["/trips/{tripId}/board", "/trips/{tripId}/start"]:
    PATHS[_p]["post"]["description"] = PATHS[_p]["post"].get("description", "") + " v0.18.8: " + AW["pin"]["compat"]
PATHS["/legal/{country}"]["get"].setdefault("parameters", []).append(q("zoneId", ref("Id"), "v0.18.8: fills {waitingRules} with this zone's live numbers (contract.json#arrivedWaiting.termsTexts)."))
PATHS["/legal/{country}"]["get"]["description"] += " v0.18.8: " + AW["termsTexts"]["note"]
