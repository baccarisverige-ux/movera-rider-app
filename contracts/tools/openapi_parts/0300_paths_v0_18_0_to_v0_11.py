# Split from tools/gen_openapi.py (rule 25, no behaviour change): run by it in name order with its globals.
# ---- Deprecated aliases
o = op("get", "/rides/{rideId}", "getRideDeprecated", "Deprecated alias of GET /trips/{tripId}", ["rider"], "Deprecated",
       params=[pref("RideId")], ok=(200, TP), deprecated=True, desc="Removed after v0.3. Response is the TripProjection (tripId + rideId).")
o = op("post", "/rides/{rideId}/cancel", "cancelRideDeprecated", "Deprecated alias of POST /trips/{tripId}/cancel", ["rider"], "Deprecated",
       params=[pref("RideId")], body="CancelCommand", ok=(200, TP), mutation=True, transition="cancel", deprecated=True)

# ---- v0.18.0 (owner 2026-10-29, driver group 2 "Onboarding"): onboarding settings, expiry, reminders, car rules, own company.
DOS = C["driverOnboarding"]["settings"]; LIM = DOS["limits"]
def rng(name, desc=None): return i(desc, minimum=LIM[name][0], maximum=LIM[name][1])
DOC_OR_DRAFT = {"anyOf": [ref("DocumentType"), s("A new custom type of this draft, named by its draftKey; the server puts the id in its place.", pattern="^draft:.{1,40}$")]}
S["OnboardingDocumentLists"] = obj({"driver": arr(DOC_OR_DRAFT), "fleet": arr(DOC_OR_DRAFT), "vehicle": arr(DOC_OR_DRAFT)},
                                   ["driver", "fleet", "vehicle"], "v0.18.0 (owner item 10): the documents a person (driver), a company (fleet) and a car (vehicle) need in the country.")
S["OnboardingStep"] = obj({"id": s(enum=DOS["stepIds"]), "on": b(), "days": rng("stepDays", "Days the step may take before it is late.")}, ["id", "on", "days"])
S["VehicleCategoryRule"] = obj({"category": ref("CategoryId"), "on": b(), "minYear": rng("minYear"), "minSeats": rng("minSeats"),
                                "fuels": arr(s(enum=DOS["fuels"]), uniqueItems=True)}, ["category", "on", "minYear", "minSeats", "fuels"])
CT_ = DOS["customTypes"]
S["LocalText"] = obj({"sv": s(minLength=1), "fr": s(minLength=1), "en": s(minLength=1)}, ["sv", "fr", "en"])
S["CustomDocumentType"] = obj({"id": s("Made by the server; leave out for a new type.", pattern=CT_["idPattern"]),
                               "draftKey": s("A new type only: lists may name it draft:<draftKey> until the server gives the id.", minLength=1, maxLength=40),
                               "owner": s(enum=CT_["owners"]), "kind": s(enum=CT_["kinds"]), "expires": b(),
                               "name": ref("LocalText"), "help": ref("LocalText")}, ["owner", "kind", "expires", "name", "help"], CT_["note"])
S["DocumentTypeTexts"] = obj({"name": ref("LocalText"), "help": ref("LocalText")}, [], DOS["texts"])
S["DocumentTypeInfo"] = obj({"owner": s(enum=CT_["owners"]), "kind": s(enum=["file", "acceptance", "admin_check"]), "expires": b(), "custom": b(),
                             "name": ref("LocalText"), "help": ref("LocalText")}, ["owner", "kind", "expires", "name"])
S["AdminCheckCommand"] = obj({"decision": s(enum=["approved", "rejected"]), "note": s(maxLength=1000)}, ["decision"], DOS["adminCheck"])
op("post", "/admin/drivers/{driverId}/documents/{type}/check", "adminCheckDocument", "Mark an admin_check document (info session) held", ["admin"], "Admin · People",
   params=[pref("DriverId"), {"name": "type", "in": "path", "required": True, "schema": ref("DocumentType")}], body="AdminCheckCommand", ok=(200, "Document"),
   mutation=True, permission="documents.approve", desc="v0.18.0: " + DOS["adminCheck"])
S["OnboardingSettings"] = obj(OrderedDict([
    ("version", i("Stamped by the server; 0 = the contract defaults (nothing published).", minimum=0)), ("publishedAt", ref("Timestamp")),
    ("country", ref("CountryCode")),
    ("documents", ref("OnboardingDocumentLists")),
    ("expiringTypes", arr(DOC_OR_DRAFT, uniqueItems=True, description="Types that need an expiry date when approved (contract.json#driverOnboarding.documentExpiry).")),
    ("steps", arr(ref("OnboardingStep"), minItems=1)),
    ("signUpReminders", obj({"on": b(), "everyDays": rng("remindEveryDays"), "stuckAfterDays": rng("stuckAfterDays")}, ["on", "everyDays", "stuckAfterDays"],
                            C["driverOnboarding"]["signUpReminders"]["note"])),
    ("expiry", obj({"warnDays": arr(rng("warnDays"), minItems=1, maxItems=3), "blockAtExpiry": b(C["driverOnboarding"]["documentExpiry"]["block"])},
                   ["warnDays", "blockAtExpiry"], C["driverOnboarding"]["documentExpiry"]["warn"])),
    ("customTypes", arr(ref("CustomDocumentType"), description=DOS["customTypes"]["note"])),
    ("texts", {"type": "object", "description": DOS["texts"], "additionalProperties": ref("DocumentTypeTexts")}),
    ("documentTypes", {"type": "object", "readOnly": True, "description": "Only in GET /driver/onboarding/settings. " + DOS["driverRead"], "additionalProperties": ref("DocumentTypeInfo")}),
    ("vehicles", obj({"categories": arr(ref("VehicleCategoryRule")), "warnDays": rng("vehicleWarnDays"), "autoHold": b("An expired car document takes the car off the road."),
                      "photosNeeded": b("The four photo types are required car documents.")}, ["categories", "warnDays", "autoHold", "photosNeeded"],
                     C["driverOnboarding"]["vehicleRules"]["note"])),
]), ["version", "country", "documents", "expiringTypes", "steps", "signUpReminders", "expiry", "vehicles"],
    "v0.18.0, per country only: " + DOS["note"] + " Rules: " + " ".join(DOS["rules"]), **{"x-server-only": True, "x-defaults": DOS["defaults"]})
# ---- v0.18.3 (R8 upload guides, R9 valid months, R5 names per country)
GL = DOS["guideLimits"]
GUIDE_LINE = obj({"sv": s(minLength=1, maxLength=GL["lineChars"]), "fr": s(minLength=1, maxLength=GL["lineChars"]), "en": s(minLength=1, maxLength=GL["lineChars"])}, ["sv", "fr", "en"])
S["DocumentGuide"] = obj({"checklist": arr(GUIDE_LINE, maxItems=GL["lines"]), "tips": arr(GUIDE_LINE, maxItems=GL["lines"])}, [], DOS["guides"])
S["OnboardingSettings"]["properties"]["guides"] = {"type": "object", "description": DOS["guides"], "additionalProperties": ref("DocumentGuide")}
S["OnboardingSettings"]["properties"]["validMonths"] = {"type": "object", "description": DOS["validMonths"], "additionalProperties": rng("validMonths")}
S["DocumentTypeInfo"]["properties"]["guide"] = ref("DocumentGuide")
S["DocumentTypeInfo"]["properties"]["validMonths"] = rng("validMonths", "v0.18.3 (R9): months from the issue date (settings.validMonths).")
S["DocumentTypeInfo"]["description"] = "v0.18.3: name is the country's (" + C["driverOnboarding"]["documents"]["namesByCountry"] + ")"
op("get", "/driver/onboarding/settings", "getDriverOnboardingSettings", "The onboarding settings of the driver's country", ["driver"], "Driver · Account",
   params=[q("country", ref("CountryCode"), "Only for an account with no country yet.")], ok=(200, "OnboardingSettings"), desc="v0.18.0: " + DOS["driverRead"])
RM = C["driverOnboarding"]["reminders"]
S["ReminderFix"] = obj({"target": s(enum=RM["fixTargets"]), "documentType": ref("DocumentType"), "scope": s(enum=["driver", "fleet", "vehicle"]),
                        "vehicleId": ref("Id"), "contentSlot": s(enum=[C["driverOnboarding"]["infoSession"]["contentSlot"]])}, ["target"],
                       "Where a tap on the line goes: document = the upload guide of documentType (vehicleId for a car); info_session = the content slot; fleet_vehicles = My fleet › cars; pick_vehicle = the car list.")
S["DriverReminder"] = obj({"kind": s(enum=list(RM["kinds"].keys())), "level": s(enum=list(RM["levels"].keys())),
                           "scope": s(enum=["driver", "fleet", "vehicle"]), "documentType": ref("DocumentType"), "documentId": ref("Id"), "vehicleId": ref("Id"),
                           "status": s("The shown document state (contract.json#documentStatus), e.g. waiting_for_movera.", enum=C["documentStatus"]["values"]),
                           "expiresAt": ref("Timestamp"), "daysLeft": i(C["driverOnboarding"]["documentExpiry"]["daysLeft"], minimum=0), "reviewNote": s(),
                           "fix": ref("ReminderFix")}, ["kind", "level"], "v0.18.0: " + " ".join(f"{k}: {v}." for k, v in RM["kinds"].items()))
S["DriverReminder"]["properties"]["actions"] = arr(ref("ReminderFix"), description="v0.18.3: " + RM["actions"])
S["DriverReminderList"] = obj({"items": arr(ref("DriverReminder")), "blocksOnline": i("Lines with level blocks_online.", minimum=0)}, ["items", "blocksOnline"], RM["note"])
op("get", "/driver/reminders", "getDriverReminders", "Important reminders for the Home sheet", ["driver"], "Driver · Account", ok=(200, "DriverReminderList"),
   desc="v0.18.0: " + RM["note"])
SC = C["driverOnboarding"]["startCompany"]
S["StartCompanyRequest"] = obj(dict(EV, company=ref("FleetCompany")), ["expectedVersion", "company"], "v0.18.0: " + SC["note"])
op("post", "/driver/fleet/start-company", "startOwnCompany", "Start my own company: the account becomes a fleet (waits for Movera)", ["driver"], "Driver · Fleet",
   body="StartCompanyRequest", ok=(200, "Driver"), mutation=True, desc="v0.18.0: " + SC["note"])
VR = C["driverOnboarding"]["vehicleRules"]
FUEL = s("v0.18.0: the car's fuel (contract.json#driverOnboarding.settings.fuels).", enum=DOS["fuels"])
S["VehicleRequest"]["properties"]["fuel"] = FUEL
S["VehicleRequest"]["description"] = "v0.18.0: " + VR["note"]
S["Vehicle"]["properties"]["fuel"] = dict(FUEL)
S["Driver"]["properties"]["signUp"] = obj({"since": ref("Timestamp"), "stuck": b("Signed up at least signUpReminders.stuckAfterDays ago and not active."),
                                           "remindersSent": i(minimum=0), "lastReminderAt": ref("Timestamp")}, ["since", "stuck", "remindersSent"],
                                          "v0.18.0, admin view only, while the account is pending or on_hold: " + C["driverOnboarding"]["signUpReminders"]["note"])
S["DocumentReviewCommand"]["description"] += " v0.18.0: " + C["driverOnboarding"]["documentExpiry"]["note"]
S["DocumentReviewCommand"]["properties"]["issuedAt"] = ref("Timestamp")
S["Vehicle"]["properties"]["ruleProblems"] = arr(s(), description="v0.18.3 (admin and fleet-owner views): " + C["driverOnboarding"]["vehicleRules"]["approval"] + " " + C["driverOnboarding"]["vehicleRules"]["baseYear"])
S["Notification"]["description"] = "v0.18.3 review notices: " + C["driverOnboarding"]["reviewNotices"]["note"]
# ---- v0.18.3 (R7): push to a closed phone through Firebase Cloud Messaging
PD = AU["devices"]
S["PushWebConfig"] = obj({"apiKey": s("Public Firebase web API key (not a secret)."), "appId": s(), "messagingSenderId": s(), "projectId": s(),
                          "authDomain": s()}, ["apiKey", "appId", "messagingSenderId", "projectId"], "v0.18.3: the Firebase web app's public settings.")
S["PushConfig"] = obj({"provider": s(enum=["fcm"]), "enabled": b("False when the server has no Firebase settings; the app then skips push."),
                       "projectId": s(), "webConfig": ref("PushWebConfig")}, ["provider", "enabled"], PD["config"]["note"])
o = op("get", "/push/config", "getPushConfig", "Public push settings for the app (Firebase web config)", ["rider", "driver"], "Auth",
       params=[{"name": "app", "in": "query", "required": True, "schema": s(enum=PD["config"]["apps"])}], ok=(200, "PushConfig"),
       desc=PD["config"]["note"] + " " + PD["appFlow"])
o["security"] = []
PATHS["/push/devices"]["post"]["description"] += " v0.18.3: " + PD["sending"]["note"] + " " + PD["sending"]["riderConsent"]

# ---- v0.18.0: group 2 admin actions on live (contract.json#driverOnboarding.adminActions)
AA = C["driverOnboarding"]["adminActions"]
S["AdminVehicleUpdate"] = obj(dict(EV, make=s(minLength=1), model=s(minLength=1), year=i(minimum=1950, maximum=2100), color=s(minLength=1), plate=s(minLength=1),
                                  seats=i(minimum=1, maximum=20), fuel=s(enum=DOS["fuels"]), categoryIds=arr(ref("CategoryId"))), ["expectedVersion"], AA["updateVehicle"])
op("patch", "/admin/vehicles/{vehicleId}", "adminUpdateVehicle", "Update a car (year, seats, fuel, categories …) within the car rules", ["admin"], "Admin · People",
   params=[pref("VehicleId")], body="AdminVehicleUpdate", ok=(200, "Vehicle"), mutation=True, permission="vehicles.edit", desc="v0.18.0: " + AA["note"] + " " + AA["updateVehicle"])
S["AdminVehicleDriverCommand"] = obj(dict(EV, driverId={"oneOf": [ref("Id"), {"type": "null"}]}), ["expectedVersion", "driverId"], AA["linkDriver"])
op("post", "/admin/vehicles/{vehicleId}/driver", "adminLinkVehicleDriver", "Link a car to a driver of its fleet (or free it)", ["admin"], "Admin · People",
   params=[pref("VehicleId")], body="AdminVehicleDriverCommand", ok=(200, "Vehicle"), mutation=True, permission="vehicles.edit", desc="v0.18.0: " + AA["note"] + " " + AA["linkDriver"])
S["AdminDriverCategoriesCommand"] = obj(dict(EV, categoryIds=arr(ref("CategoryId"), minItems=1, uniqueItems=True)), ["expectedVersion", "categoryIds"], AA["driverCategories"])
op("put", "/admin/drivers/{driverId}/categories", "adminSetDriverCategories", "Set the categories a driver takes (only what his car fits)", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="AdminDriverCategoriesCommand", ok=(200, "Driver"), mutation=True, permission="vehicles.edit", desc="v0.18.0: " + AA["note"] + " " + AA["driverCategories"])
S["AdminBankReviewCommand"] = obj({"decision": s(enum=["approved", "rejected"]), "note": s(maxLength=1000)}, ["decision"], AA["bankReview"])
op("post", "/admin/drivers/{driverId}/bank/review", "adminReviewDriverBank", "Approve or reject a driver's bank details", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="AdminBankReviewCommand", ok=(200, "Document"), mutation=True, permission="documents.approve", desc="v0.18.0: " + AA["note"] + " " + AA["bankReview"])

# ---- v0.18.0 (owner decision 19): car documents for the fleet owner only; members see pickable.
CD = C["driverOnboarding"]["carDocuments"]
S["Vehicle"]["properties"]["pickable"] = b("v0.18.0: the asking driver can pick this car now. " + CD["note"])
S["Vehicle"]["properties"]["notPickableReason"] = s("v0.18.0: why not (pickable false); the app says \"Can't be driven\".", enum=CD["notPickableReasons"])

# ---------------------------------------------------------------- document
TAG_DESC = {"Admin · System": "Crashes & errors from the apps and the server, grouped (v0.16.0)", "Admin · Zones": "Zones from the server: list, create, outline, open and close (v0.11.0)", "Auth": "Sign-in, tokens and push devices for the rider and driver apps (v0.5.0)", "Admin · Auth": "Admin panel sign-in with e-mail and password (v0.5.1)",
            "Maps": "Address search, geocoding and road routes through the server (v0.5.1); read-only, no Idempotency-Key",
            "Telemetry": "Fire-and-forget app logs, analytics and crashes (v0.5.1); no auth required", "Trips": "Shared trip resource (rider, driver, admin)", "Realtime": "Streams: SSE (or WebSocket) + JSON replay",
            "Deprecated": "Legacy /rides aliases kept for one release"}
# ---- v0.7.1: pricing rework part 2 (owner Pricing decisions 2026-10-27)
CC = C["categoryCatalog"]
PARAMS["CategoryIdPath"] = {"name": "categoryId", "in": "path", "required": True, "schema": ref("CategoryId")}
PARAMS["StopIndex"] = {"name": "stopIndex", "in": "path", "required": True, "schema": {"type": "integer", "minimum": 0, "maximum": 9}, "description": "0-based index into TripProjection.stops."}
S["StopVisit"] = obj({"stopIndex": i(minimum=0), "arrivedAt": ref("Timestamp"), "leftAt": ref("Timestamp")}, ["stopIndex", "arrivedAt"],
                     "v0.7.1: one extra stop the driver arrived at (contract.json#stopWaits); stop_waiting runs from arrivedAt to leftAt (or to complete).")
S["StopCommand"] = obj(dict(EV), ["expectedVersion"], "v0.7.1: the driver's arrived-at-stop or leaving-stop tap.")
for verb, oid, summ in [("arrive", "driverArriveAtStop", "Driver arrived at an extra stop (stop waiting starts)"), ("leave", "driverLeaveStop", "Driver leaves an extra stop (stop waiting ends)")]:
    op("post", "/driver/trips/{tripId}/stops/{stopIndex}/" + verb, oid, summ, ["driver"], "Driver · Trip", params=TID + [pref("StopIndex")], body="StopCommand",
       ok=(200, "TripProjection"), mutation=True, desc="v0.7.1. " + C["stopWaits"][verb])
S["ConfigHistoryEntry"] = obj({"doc": ref("ConfigDocName"), "zoneId": ref("Id"), "version": i(minimum=1), "publishedAt": ref("Timestamp"), "publishedBy": ref("Id"),
                               "note": s(), "action": s(enum=["publish", "restore"]), "restoredFrom": i(minimum=1), "document": {"type": "object"}},
                              ["doc", "zoneId", "version", "publishedAt", "action", "document"], "v0.7.1: one published version (contract.json#pricingHistory).")
S["ConfigHistoryEntryPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("ConfigHistoryEntry"))}}]}
S["ConfigRestoreCommand"] = obj(dict(EV, zoneId=ref("Id"), version=i("The version to publish again.", minimum=1), note=s(maxLength=1000)), ["expectedVersion", "zoneId", "version"])
op("get", "/admin/config/{doc}/history", "adminConfigHistory", "Published versions of a config document, newest first", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc"), q("zoneId", ref("Id")), pref("Cursor"), pref("Limit")], ok=(200, "ConfigHistoryEntryPage"), permission="settings.read", desc="v0.7.1. " + C["pricingHistory"]["list"])
op("post", "/admin/config/{doc}/restore", "adminRestoreConfig", "Publish an earlier version again (Restore, Undo last publish)", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigRestoreCommand", ok=(200, "ConfigPublication"), mutation=True, permission="settings.publish",
   desc="v0.7.1. " + C["pricingHistory"]["restore"] + " " + C["pricingHistory"]["audit"])
S["CategoryDef"] = obj({"id": ref("CategoryId"), "label": s(minLength=1, maxLength=40), "line": ref("LocalizedLine"), "seats": i(minimum=1, maximum=8),
                        "builtIn": b("A seed category."), "sort": i(minimum=0), "archivedAt": ref("Timestamp"), "archivedBy": ref("Id"), "archiveReason": s(),
                        "restoreUntil": ref("Timestamp")}, ["id", "label", "line", "seats", "builtIn", "sort"], "v0.7.1: " + CC["entity"])
S["CategoryDefList"] = obj({"categories": arr(ref("CategoryDef")), "restoreDays": i(minimum=1)}, ["categories", "restoreDays"], "Active first, then the archived ones still restorable.")
S["CategoryDefInput"] = obj({"id": ref("CategoryId"), "label": s(minLength=1, maxLength=40), "line": ref("LocalizedLine"), "seats": i(minimum=1, maximum=8), "sort": i(minimum=0)},
                            ["label", "line", "seats"], "id only on create (else made from the label).")
S["CategoryArchiveCommand"] = obj({"reason": s(minLength=1, maxLength=500)}, ["reason"])
op("get", "/admin/categories", "adminListCategories", "The car type catalog (every zone)", ["admin"], "Admin · Config", ok=(200, "CategoryDefList"), permission="settings.read", desc="v0.7.1. " + CC["note"])
op("post", "/admin/categories", "adminCreateCategory", "Add a car type (off in every zone)", ["admin"], "Admin · Config", body="CategoryDefInput", ok=(201, "CategoryDef"), mutation=True, permission="settings.publish")
op("put", "/admin/categories/{categoryId}", "adminUpdateCategory", "Rename a car type, its sub-line and seats", ["admin"], "Admin · Config", params=[pref("CategoryIdPath")], body="CategoryDefInput", ok=(200, "CategoryDef"), mutation=True, permission="settings.publish")
op("post", "/admin/categories/{categoryId}/archive", "adminArchiveCategory", "Delete a car type (archived, restorable)", ["admin"], "Admin · Config", params=[pref("CategoryIdPath")], body="CategoryArchiveCommand", ok=(200, "CategoryDef"), mutation=True, permission="settings.publish", desc="v0.7.1. " + CC["archive"])
op("post", "/admin/categories/{categoryId}/restore", "adminRestoreCategory", "Restore an archived car type (old prices, off)", ["admin"], "Admin · Config", params=[pref("CategoryIdPath")], ok=(200, "CategoryDef"), mutation=True, permission="settings.publish", desc="v0.7.1. " + CC["restore"])

# ---- v0.7.2: real surge data for the admin, the driver's surge map, one admin everywhere (owner 2026-10-28)
SL = C["surgeLive"]; DSM = C["driverSurgeMap"]
S["SurgeSource"] = s(enum=["manual", "scheduled", "smart", "off"])
S["ZoneSurgeNow"] = obj({"zoneId": ref("Id"), "multiplier": n(minimum=1, maximum=6), "source": ref("SurgeSource"), "until": ref("Timestamp"), "scheduleId": ref("Id"),
                         "profileId": s(), "requests": i(minimum=0), "freeDrivers": i(minimum=0), "ratio": n(minimum=0), "checkedAt": ref("Timestamp")},
                        ["zoneId", "multiplier", "source", "requests", "freeDrivers", "ratio"], "v0.7.2: " + SL["now"])
S["SurgeNowList"] = obj({"at": ref("Timestamp"), "zones": arr(ref("ZoneSurgeNow"))}, ["at", "zones"])
S["SurgePoint"] = obj({"at": ref("Timestamp"), "requests": i(minimum=0), "freeDrivers": i(minimum=0), "ratio": n(minimum=0), "multiplier": n(minimum=1, maximum=6)},
                      ["at", "requests", "freeDrivers", "ratio", "multiplier"], "v0.7.2: " + SL["points"])
S["PriceCheck"] = obj({"windowMin": i(minimum=1), "saw": i(minimum=0), "left": i(minimum=0), "leftPct": i(minimum=0, maximum=100)}, ["windowMin", "saw", "left", "leftPct"], "v0.7.2: " + SL["priceCheck"])
S["SurgeEffect"] = obj({"drivers": i(), "ridesPct": i(), "leftPct": i(minimum=0, maximum=100)}, ["drivers", "ridesPct", "leftPct"])
S["SurgeTimelineItem"] = obj({"at": ref("Timestamp"), "kind": s(enum=["manual_start", "manual_stop", "scheduled_start", "scheduled_end", "smart_change", "smart_end"]),
                              "multiplier": n(minimum=1, maximum=6), "previous": n(minimum=1, maximum=6), "by": s(), "profileId": s(), "effect": ref("SurgeEffect")},
                             ["at", "kind", "multiplier"], "v0.7.2: " + SL["timeline"])
S["SurgeHistory"] = obj({"zoneId": ref("Id"), "from": ref("Timestamp"), "to": ref("Timestamp"), "bucketMin": i(enum=[5, 10, 15, 30, 60]),
                         "points": arr(ref("SurgePoint")), "priceCheck": ref("PriceCheck"), "timeline": arr(ref("SurgeTimelineItem"))},
                        ["zoneId", "from", "to", "bucketMin", "points", "priceCheck", "timeline"], "v0.7.2: " + SL["history"])
op("get", "/admin/surge/now", "adminSurgeNow", "The surge now in each zone, with its demand", ["admin"], "Admin · Config",
   params=[q("zoneIds", s("Comma-separated zone ids; none = every zone in the admin's scope."))], ok=(200, "SurgeNowList"), permission="settings.read", desc="v0.7.2. " + SL["note"] + " " + SL["now"])
op("get", "/admin/zones/{zoneId}/surge/history", "adminSurgeHistory", "Demand chart, rider price check and surge timeline of a zone", ["admin"], "Admin · Config",
   params=[pref("ZoneId"), q("hours", i(minimum=1, maximum=24, default=6)), q("bucketMin", i(enum=[5, 10, 15, 30, 60], default=10))], ok=(200, "SurgeHistory"), permission="settings.read",
   desc="v0.7.2. " + SL["history"] + " " + SL["samples"])
S["SurgeLevel"] = s(enum=["low", "medium", "high"], description="v0.7.2: " + DSM["levels"])
S["ZoneBounds"] = obj({"south": n(minimum=-90, maximum=90), "west": n(minimum=-180, maximum=180), "north": n(minimum=-90, maximum=90), "east": n(minimum=-180, maximum=180)}, ["south", "west", "north", "east"])
S["DriverSurgeZone"] = obj({"zoneId": ref("Id"), "level": ref("SurgeLevel"), "bounds": ref("ZoneBounds")}, ["zoneId", "level", "bounds"], "v0.7.2: never the multiplier.")
S["DriverSurgeMap"] = obj({"at": ref("Timestamp"), "zones": arr(ref("DriverSurgeZone"))}, ["at", "zones"], "v0.7.2: " + DSM["note"])
op("get", "/driver/surge-map", "driverSurgeMap", "Zones with a surge now, as colour levels for the Home map", ["driver"], "Driver · Session",
   ok=(200, "DriverSurgeMap"), desc="v0.7.2. " + DSM["route"] + " " + DSM["refresh"] + " " + DSM["tip"])

# ---- v0.10.0: content from the admin to the apps (owner Content answers 2026-10-28)
CT = C["content"]
S["ContentSlot"] = s(enum=CT["slots"])
S["ContentText"] = obj({"sv": s(minLength=1, maxLength=4000), "fr": s(minLength=1, maxLength=4000), "en": s(minLength=1, maxLength=4000)}, ["sv", "fr", "en"])
S["AppVersionPair"] = obj({"min": s(pattern="^\\d+\\.\\d+\\.\\d+$"), "recommended": s(pattern="^\\d+\\.\\d+\\.\\d+$")}, ["min", "recommended"])
S["AppVersions"] = obj({"rider": ref("AppVersionPair"), "driver": ref("AppVersionPair")}, ["rider", "driver"])
S["ContentItem"] = obj({"slot": ref("ContentSlot"), "zoneId": ref("Id"), "version": i(minimum=1), "publishedAt": ref("Timestamp"), "publishedBy": ref("Id"),
                        "title": s(minLength=1, maxLength=200), "text": ref("ContentText"), "image": s(format="uri", pattern="^https://"), "expiresAt": ref("Timestamp"),
                        "reaccept": b("legal only"), "versions": ref("AppVersions")}, ["slot", "zoneId", "version", "publishedAt", "title", "text"], "v0.10.0: " + CT["item"])
S["ContentList"] = obj({"items": arr(ref("ContentItem"))}, ["items"])
S["ContentPublishCommand"] = obj({"zoneIds": arr(ref("Id"), minItems=1), "title": s(minLength=1, maxLength=200), "text": ref("ContentText"), "image": s(pattern="^https://"),
                                  "expiresAt": ref("Timestamp"), "reaccept": b(), "versions": ref("AppVersions")}, ["zoneIds", "title", "text"])
S["ContentRollbackCommand"] = obj({"zoneId": ref("Id"), "version": i(minimum=1)}, ["zoneId", "version"])
S["TermsAcceptCommand"] = obj({"contentVersion": i(minimum=1)}, ["contentVersion"])
PARAMS["ContentSlotPath"] = {"name": "slot", "in": "path", "required": True, "schema": ref("ContentSlot")}
op("get", "/admin/content", "adminListContent", "The zone's published content", ["admin"], "Admin · Config", params=[q("zoneId", ref("Id"))], ok=(200, "ContentList"), permission="settings.read", desc="v0.10.0. " + CT["admin"])
op("post", "/admin/content/{slot}/publish", "adminPublishContent", "Publish a content place to the chosen zones", ["admin"], "Admin · Config", params=[pref("ContentSlotPath")], body="ContentPublishCommand", ok=(200, "ContentList"), mutation=True, permission="settings.publish", desc="v0.10.0. " + CT["note"])
op("get", "/admin/content/{slot}/history", "adminContentHistory", "Published versions of a content place in a zone", ["admin"], "Admin · Config", params=[pref("ContentSlotPath"), q("zoneId", ref("Id"))], ok=(200, "ContentList"), permission="settings.read")
op("post", "/admin/content/{slot}/rollback", "adminRollbackContent", "Publish an earlier version again", ["admin"], "Admin · Config", params=[pref("ContentSlotPath")], body="ContentRollbackCommand", ok=(200, "ContentItem"), mutation=True, permission="settings.publish")
S["TermsAcceptance"] = obj({"actor": s(enum=["rider", "driver"]), "subjectId": ref("Id"), "zoneId": ref("Id"), "contentVersion": i(minimum=1), "acceptedAt": ref("Timestamp")}, ["actor", "subjectId", "zoneId", "contentVersion", "acceptedAt"])
S["TermsAcceptanceList"] = obj({"items": arr(ref("TermsAcceptance"))}, ["items"])
op("get", "/admin/content/legal/acceptances", "adminTermsAcceptances", "Who accepted the zone's legal terms, and when", ["admin"], "Admin · Config", params=[q("zoneId", ref("Id"))], ok=(200, "TermsAcceptanceList"), permission="settings.read",
   desc="v0.10.0. An accept counts for every zone whose live legal version has that number; a version no zone has live → 409 conflict (terms_version_not_current).")
op("get", "/rider/content", "riderContent", "Content for the rider app", ["rider"], "Rider · Config", params=[q("zoneId", ref("Id"))], ok=(200, "ContentList"), desc="v0.10.0. " + CT["apps_read"] + " " + CT["appVersions"])
op("get", "/driver/content", "driverContent", "Content for the driver app", ["driver"], "Driver · Session", params=[q("zoneId", ref("Id"))], ok=(200, "ContentList"), desc="v0.10.0. " + CT["apps_read"] + " " + CT["appVersions"])
op("post", "/account/terms/accept", "acceptTerms", "Accept the published legal terms", ["rider", "driver"], "Account", body="TermsAcceptCommand", ok=(204, None), mutation=True, desc="v0.10.0. " + CT["legal"])

# ---- v0.11.0: zones from the server (owner 2026-10-28, decision #9)
ZN = C["zones"]
TZ = s(pattern=r"^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)*$")
S["ZoneNames"] = obj({"sv": s(minLength=1, maxLength=80), "fr": s(minLength=1, maxLength=80), "en": s(minLength=1, maxLength=80)}, ["sv", "fr", "en"], ZN["names"])
S["ZoneKind"] = s(enum=["operating", "airport"])
S["ZonePoint"] = arr(n(), minItems=2, maxItems=2, description="[lat, lng]")
S["ZonePolygon"] = arr(ref("ZonePoint"), minItems=3, maxItems=500, description=ZN["polygon"])
S["Zone"] = obj({"zoneId": ref("Id"), "names": ref("ZoneNames"), "country": ref("CountryCode"), "currency": ref("CurrencyCode"), "timeZone": TZ,
                 "kind": ref("ZoneKind"), "polygon": ref("ZonePolygon"), "bounds": ref("ZoneBounds"), "center": obj({"lat": n(), "lng": n()}, ["lat", "lng"]),
                 "open": b(), "version": i(minimum=1), "createdAt": ref("Timestamp"), "updatedAt": ref("Timestamp"), "updatedBy": ref("Id")},
                ["zoneId", "names", "country", "currency", "timeZone", "kind", "polygon", "bounds", "center", "open", "version"], "v0.11.0: " + ZN["zone"] + " " + ZN["idScheme"])
S["ZoneList"] = obj({"zones": arr(ref("Zone"))}, ["zones"])
S["ZoneCreateCommand"] = obj({"zoneId": ref("Id"), "names": ref("ZoneNames"), "country": ref("CountryCode"), "currency": ref("CurrencyCode"), "timeZone": TZ,
                              "kind": ref("ZoneKind"), "polygon": ref("ZonePolygon"), "open": b("default false")},
                             ["zoneId", "names", "country", "currency", "timeZone", "polygon"], "A new zone starts closed unless open is true. 409 conflict zone_exists when the id is taken.")
S["ZoneUpdateCommand"] = obj({**EV, "names": ref("ZoneNames"), "kind": ref("ZoneKind"), "polygon": ref("ZonePolygon")}, ["expectedVersion"], ZN["version"])
S["ZoneOpenCommand"] = obj({**EV, "note": s(maxLength=1000)}, ["expectedVersion"])
op("get", "/admin/zones", "adminListZones", "Every zone in the admin's scope, open and closed", ["admin"], "Admin · Zones", params=[q("country", ref("CountryCode"))], ok=(200, "ZoneList"), permission="zones.read", desc="v0.11.0. " + ZN["permissions"])
op("post", "/admin/zones", "adminCreateZone", "Create a zone", ["admin"], "Admin · Zones", body="ZoneCreateCommand", ok=(201, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["idScheme"] + " " + ZN["neverDeleted"])
op("put", "/admin/zones/{zoneId}", "adminUpdateZone", "Change a zone's names, kind or outline", ["admin"], "Admin · Zones", params=[pref("ZoneId")], body="ZoneUpdateCommand", ok=(200, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["polygon"])
op("post", "/admin/zones/{zoneId}/open", "adminOpenZone", "Open a zone for new rides", ["admin"], "Admin · Zones", params=[pref("ZoneId")], body="ZoneOpenCommand", ok=(200, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["open"])
op("post", "/admin/zones/{zoneId}/close", "adminCloseZone", "Close a zone (never deleted)", ["admin"], "Admin · Zones", params=[pref("ZoneId")], body="ZoneOpenCommand", ok=(200, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["open"] + " " + ZN["neverDeleted"])
op("get", "/rider/zones", "riderZones", "The open zones, with outline and names", ["rider"], "Rider · Config", params=[q("country", ref("CountryCode"))], ok=(200, "ZoneList"), desc="v0.11.0. " + ZN["apps"] + " " + ZN["notHere"])
op("get", "/driver/zones", "driverZones", "The open zones, with outline and names", ["driver"], "Driver · Session", params=[q("country", ref("CountryCode"))], ok=(200, "ZoneList"), desc="v0.11.0. " + ZN["apps"])
