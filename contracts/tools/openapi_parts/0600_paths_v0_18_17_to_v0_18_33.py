# Split from tools/gen_openapi.py (rule 25, no behaviour change): run by it in name order with its globals.
# v0.18.17 Book later (CONTRACT.md §41, contract.json#bookLater): booked rides end to end.
BL = C["bookLater"]
_RD = C["configDefaults"]["reservations"]
for _k, _sch in [("minAheadMin", i("v0.18.17 (owner Q1): the earliest pickup, minutes after booking. " + BL["window"], minimum=5, maximum=240)),
                 ("maxAheadDays", i("v0.18.17 (owner Q1): the latest pickup, days after booking.", minimum=1, maximum=365)),
                 ("soonBeforeMin", i("v0.18.17 (owner Q2): a booking closer than this goes out at once like a live ride; else to the Scheduled rides list. " + BL["plan"], minimum=0, maximum=240)),
                 ("listTo", s("v0.18.17: who sees a new booked ride in Scheduled rides. " + BL["listTo"]["rules"], enum=BL["listTo"]["values"])),
                 ("listMinRating", n(minimum=1, maximum=5)), ("listGroupSize", i(minimum=1, maximum=500)), ("listNearKm", n(minimum=0.5, maximum=50)),
                 ("listAreaTrips", i(minimum=1, maximum=200)), ("listGroupId", {"oneOf": [ref("Id"), {"type": "null"}]}),
                 ("listOpenAll", b("v0.18.17: untaken after listOpenAllAfterMin minutes, every driver of the zone sees it.")), ("listOpenAllAfterMin", i(minimum=1, maximum=1440)),
                 ("noticeOn", b("v0.18.17 (owner Q2): the reservation notice (push reservation_new) at booking.")),
                 ("noticeMaxDrivers", i("v0.18.17: at most this many drivers get the notice, nearest to the pickup first.", minimum=1, maximum=500)),
                 ("homePopup", b("v0.18.17: untaken after homePopupAfterMin minutes, a second notice (reservation_popup, the Home popup).")),
                 ("noDriverAlertMin", i("v0.18.17 (owner Q3): no driver this many minutes before pickup → admin alert + rider told; the search goes on. " + BL["noDriver"], minimum=1, maximum=120)),
                 ("riderReminderMin", i("v0.18.17 (owner Q5 rider): rider reminder this many minutes before pickup; 0 = off.", minimum=0, maximum=1440)),
                 ("maxTripKm", {"oneOf": [n(minimum=1, maximum=1000), {"type": "null"}], "description": "v0.18.17: the longest booked ride in km (the demo admin's Max Trip Distance (Reservations)); null = no limit (owner BL-Q5); longer → 400 trip_too_long at quote."}),
                 ("dispatchBeforeMin", i("v0.18.17 (owner BL-Q2): untaken, the search starts this many minutes before pickup.", minimum=5, maximum=240)),
                 ("listHomeKm", n(minimum=0.5, maximum=50)), ("listAtTimeKm", n(minimum=0.5, maximum=50)), ("listAtTimeMin", i(minimum=5, maximum=240)),
                 ("arriveEarlyMin", i("v0.18.19 (owner): the driver should arrive this many minutes before the pickup time; leaveAt is worked out from it.", minimum=0, maximum=60)),
                 ("changeAnswerMin", i("v0.18.17 (owner BL-Q6): how long the driver has to answer 'Keep it at the new time?'.", minimum=1, maximum=120)),
                 ("freeChangeBeforeMin", i("v0.18.17 (owner Q6): change or cancel free only more than this many minutes before pickup. " + BL["rider"]["change"], minimum=0, maximum=1440))]:
    S["DriverReservations"]["properties"][_k] = dflt(_sch, _RD[_k])
for _k in ("minAheadMin", "maxAheadDays", "freeChangeBeforeMin"):
    S["RiderAppConfig"]["properties"]["booking"]["properties"][_k] = {**S["DriverReservations"]["properties"][_k], "description": "v0.18.17: written by the server from the zone's DriverAppConfig.reservations." + _k}
S["DriverReservations"]["properties"]["raiseFare"] = dflt(b("v0.18.19 (owner C): an admin may raise the driver's fare of a booked ride (POST /admin/trips/{tripId}/driver-bonus, the same call and the same Pricing bonus limit as a live ride). false: the server refuses it for kind scheduled (403 forbidden, reason raise_off). Missing = true."), True)
S["DriverReservations"]["properties"]["raiseMax"] = {"oneOf": [n(minimum=0), {"type": "null"}], "default": None, "description": "v0.18.19 (owner C): the highest raise of a booked ride, in the zone's money (major units, e.g. 500 = 500 kr); the server also keeps the live-ride bonus limit, whichever is lower. Missing or null = the live-ride limit only. Over it: 400 invalid_request, reason bonus_over_limit."}
S["RiderAppConfig"]["properties"]["booking"]["properties"]["reservationsOn"] = b("v0.18.19 (owner A): the zone's Book later switch (DriverAppConfig.reservations.on), written by the server. Off: the app still shows Book later and says 'Not available in this area yet' when tapped; the server refuses (403 reservations_off).")
S["ReservationInfo"] = obj({"mode": s(enum=["now", "list"]), "dispatchAt": ref("Timestamp"), "freeChangeUntil": ref("Timestamp"), "noDriver": b(BL["noDriver"]), "overdue": b("BL-Q7: the pickup time passed with no driver."), "notStarted": b(), "atRisk": b("v0.18.19: the driver may be late."), "leaveAt": ref("Timestamp"), "driveSeconds": i(minimum=0),
                            "changeAsk": obj({"until": ref("Timestamp"), "previousAt": ref("Timestamp")}, ["until", "previousAt"], BL["rider"]["change"]),
                            "mustBeOnlineAt": {"allOf": [ref("Timestamp")], "description": "Driver and admin views of an accepted ride."}},
                           ["mode", "dispatchAt", "freeChangeUntil", "noDriver"], "v0.18.17: " + BL["rider"]["projection"])
S["TripProjection"]["properties"]["reservation"] = {"allOf": [ref("ReservationInfo")], "description": "v0.18.17: kind scheduled only."}
S["ReservationInfo"]["properties"]["noDriverFound"] = b("v0.18.39 §63 (P17, contract.json#noDriverNearby.bookedStop): the server ended this booked ride, no driver was found (no fee).")
S["DriverReservation"] = obj(OrderedDict([("tripId", ref("Id")), ("version", i(minimum=1)), ("scheduledAt", ref("Timestamp")), ("categoryId", ref("CategoryId")),
                              ("rideType", s(BL["driver"]["rideType"], enum=["normal", "airport", "longTrip", "comfortPremium", "event"])),
                              ("pickup", ref("Place")), ("dropoff", ref("Place")), ("stops", i(minimum=0)), ("distanceMeters", i(minimum=0)), ("durationSeconds", i(minimum=0)),
                              ("earnings", ref("Money")), ("status", ref("TripStatus")), ("mustBeOnlineAt", ref("Timestamp")), ("canStartAt", ref("Timestamp")),
                              ("popup", b("The Home popup step was reached (reservation_popup sent).")),
                              ("riderFirstName", s(description="v0.18.32 (contract.json#bookedRideSeen.leaveNowName): scope=accepted only, the rider's first name for the leave-now popup.")),
                              ("reservation", {"allOf": [ref("ReservationInfo")], "description": "v0.18.19 (live test HIGH 2): the same reservation as the trip read, so the list knows changeAsk (Keep it at the new time?) and leaveAt."})]),
                             ["tripId", "version", "scheduledAt", "categoryId", "rideType", "pickup", "dropoff", "earnings", "status", "mustBeOnlineAt", "canStartAt"], "v0.18.17: one booked ride in the driver's lists.")
S["DriverReservationPage"] = obj({"items": arr(ref("DriverReservation")), "nextCursor": {"oneOf": [s(), {"type": "null"}]}}, ["items", "nextCursor"], "v0.18.17.")
S["ReservationAcceptCommand"] = obj({"expectedVersion": i(minimum=1)}, (), "v0.18.17.")
S["ReservationReleaseCommand"] = obj({"reasonCode": ref("ScheduledCancelReasonCode"), "note": s(maxLength=1000)}, ["reasonCode"], "v0.18.17: " + BL["driver"]["release"])
S["RescheduleCommand"] = obj({"quoteId": ref("Id"), "expectedVersion": i(minimum=1)}, ["quoteId", "expectedVersion"], "v0.18.17: " + BL["rider"]["change"])
S["AdminReservationCommand"] = obj({"expectedVersion": i(minimum=1), "reason": s(minLength=1, maxLength=500)}, ["expectedVersion"], "v0.18.17: reason is required for unassign.")
PATHS["/driver/reservations"]["get"]["responses"]["200"]["content"]["application/json"]["schema"] = {"oneOf": [ref("DriverReservationPage"), ref("TripProjectionPage")]}
PATHS["/driver/reservations"]["get"]["responses"]["200"]["description"] = "v0.18.17: scope=open → DriverReservationPage; scope=accepted → DriverReservationPage of the driver's accepted rides. " + BL["driver"]["list"]
PATHS["/driver/reservations"]["get"]["responses"]["200"]["content"]["application/json"]["schema"] = ref("DriverReservationPage")
RTID = [{"name": "tripId", "in": "path", "required": True, "schema": ref("Id")}]
op("post", "/driver/reservations/{tripId}/accept", "acceptReservation", "Take a booked ride from Scheduled rides", ["driver"], "Driver · Offers", params=RTID, body="ReservationAcceptCommand", ok=(200, TP), mutation=True, transition="accept", desc="v0.18.17. " + BL["driver"]["accept"])
op("post", "/driver/reservations/{tripId}/release", "releaseReservation", "Give a booked ride back", ["driver"], "Driver · Offers", params=RTID, body="ReservationReleaseCommand", ok=(204, None), mutation=True, transition="cancel", desc="v0.18.17. " + BL["driver"]["release"])
op("post", "/driver/reservations/{tripId}/start", "startReservation", "Start driving to a booked ride's pickup", ["driver"], "Driver · Offers", params=RTID, body="ReservationAcceptCommand", ok=(200, TP), mutation=True, transition="head_to_pickup", desc="v0.18.17. " + BL["driver"]["start"])
S["ReservationKeepCommand"] = obj({"keep": b()}, ["keep"], "v0.18.17: " + BL["driver"]["keep"])
S["HomeArea"] = obj({"lat": n(minimum=-90, maximum=90), "lng": n(minimum=-180, maximum=180), "label": s(maxLength=120)}, ["lat", "lng"], "v0.18.17: " + BL["driver"]["homeArea"])
S["Driver"]["properties"]["homeArea"] = {"allOf": [ref("HomeArea")], "description": "v0.18.17 (owner BL-Q4)."}
S["FavouriteDriverList"] = obj({"items": arr(obj({"driverId": ref("Id"), "firstName": s()}, ["driverId"]))}, ["items"], "v0.18.17: " + BL["rider"]["favourites"])
op("post", "/driver/reservations/{tripId}/keep", "keepReservation", "Answer the rider's change of a booked ride", ["driver"], "Driver · Offers", params=RTID, body="ReservationKeepCommand", ok=(200, TP), mutation=True, desc="v0.18.17. " + BL["driver"]["keep"])
LF = BL["liveFixes"]
S["ReservationPolicy"] = obj({"includedWaitingMinutes": i(minimum=0, maximum=60), "rev": i(minimum=1), "updatedAt": ref("Timestamp")}, ["includedWaitingMinutes", "rev", "updatedAt"], "v0.18.19: " + LF["includedWaitingPolicy"])
S["ReservationPolicyCommand"] = obj({"expectedRev": i(minimum=1), "includedWaitingMinutes": i(minimum=0, maximum=60)}, ["expectedRev", "includedWaitingMinutes"], "v0.18.19.")
op("get", "/admin/reservations/policy", "getReservationPolicy", "The reservation policy for every zone (included waiting)", ["admin"], "Admin · Trips", ok=(200, "ReservationPolicy"), permission="trips.read", desc="v0.18.19. " + LF["includedWaitingPolicy"])
op("put", "/admin/reservations/policy", "saveReservationPolicy", "Save the reservation policy for every zone", ["admin"], "Admin · Trips", body="ReservationPolicyCommand", ok=(200, "ReservationPolicy"), mutation=True, permission="trips.intervene", desc="v0.18.19. " + LF["includedWaitingPolicy"])
op("put", "/driver/home-area", "setDriverHomeArea", "Set the driver's home area", ["driver"], "Driver · Account", body="HomeArea", ok=(200, "Driver"), mutation=True, desc="v0.18.17. " + BL["driver"]["homeArea"])
op("delete", "/driver/home-area", "clearDriverHomeArea", "Clear the driver's home area", ["driver"], "Driver · Account", ok=(200, "Driver"), mutation=True, desc="v0.18.17.")
op("get", "/rider/favourite-drivers", "listFavouriteDrivers", "The rider's favourite drivers", ["rider"], "Rider · Account", ok=(200, "FavouriteDriverList"), desc="v0.18.17. " + BL["rider"]["favourites"])
DID = [{"name": "driverId", "in": "path", "required": True, "schema": ref("Id")}]
op("put", "/rider/favourite-drivers/{driverId}", "addFavouriteDriver", "Mark a driver as favourite", ["rider"], "Rider · Account", params=DID, body="EmptyCommand", ok=(200, "FavouriteDriverList"), mutation=True, desc="v0.18.17.")
op("delete", "/rider/favourite-drivers/{driverId}", "removeFavouriteDriver", "Unmark a favourite driver", ["rider"], "Rider · Account", params=DID, ok=(200, "FavouriteDriverList"), mutation=True, desc="v0.18.17.")
op("post", "/trips/{tripId}/reschedule", "rescheduleTrip", "Change a booked ride (new quote, new price)", ["rider"], "Trips", params=TID, body="RescheduleCommand", ok=(200, TP), mutation=True, transition="reschedule", desc="v0.18.17. " + BL["rider"]["change"])
op("post", "/admin/trips/{tripId}/reservation/unassign", "adminUnassignReservation", "Take the driver off a booked ride (back to the list)", ["admin"], "Admin · Trips", params=TID, body="AdminReservationCommand", ok=(200, TP), mutation=True, transition="unassign", permission="trips.intervene", desc="v0.18.17. " + BL["admin"]["actions"])
op("post", "/admin/trips/{tripId}/reservation/dispatch-now", "adminDispatchReservationNow", "Send a booked ride to drivers now", ["admin"], "Admin · Trips", params=TID, body="AdminReservationCommand", ok=(200, TP), mutation=True, transition="start_search", permission="trips.intervene", desc="v0.18.17. " + BL["admin"]["actions"])
PATHS["/trips/{tripId}/cancel"]["post"]["description"] += " v0.18.17: " + BL["rider"]["cancel"]
S["Offer"]["properties"]["reservation"] = b("v0.18.19: a booked ride (Trip.kind scheduled): the app shows the reservation badge with scheduledAt. " + BL["liveFixes"]["badge"])
PATHS["/quotes"]["post"]["description"] = PATHS["/quotes"]["post"].get("description", "") + " v0.18.17: " + BL["window"]
PATHS["/trips"]["post"]["description"] += " v0.18.17: " + BL["window"] + " " + BL["card"]
# ---- v0.18.29 A2: hold one driver's payouts (owner build-spec Q4; contract.json#payoutHold)
PH = C["payoutHold"]
S["PayoutHold"] = obj({"reason": s(maxLength=PH["reasonMax"]), "at": ref("Timestamp"), "by": ref("Id")}, ["reason", "at"], PH["note"])
S["PayoutHoldCommand"] = obj({"held": b(), "reason": s(minLength=1, maxLength=PH["reasonMax"])}, ["held", "reason"])
S["Driver"]["properties"]["payoutHold"] = {"allOf": [ref("PayoutHold")], "description": "v0.18.29: admin view only; absent = payouts not held."}
op("post", "/admin/drivers/{driverId}/payout-hold", "adminHoldDriverPayouts", "Pause or release one driver's payouts", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="PayoutHoldCommand", ok=(200, "Driver"), mutation=True, permission="finance.edit", permission_v050="finance.edit", desc=PH["note"])

# ---- v0.18.29 A2: rider moderation (Warn → Pause → Ban, owner G16 Q16-1/Q16-2; contract.json#riderModeration)
RM = C["riderModeration"]
S["RiderModerationLevel"] = s(enum=list(RM["levels"].keys()), description="; ".join(f"{k} = {v}" for k, v in RM["levels"].items()))
S["RiderModeration"] = obj({"level": ref("RiderModerationLevel"), "reason": s(maxLength=300), "until": {"oneOf": [ref("Timestamp"), {"type": "null"}], "description": "paused: when the pause ends by itself; otherwise null."},
                            "setAt": ref("Timestamp")}, ["level"], RM["note"])
S["RiderModerationCommand"] = obj(dict(EV, level=ref("RiderModerationLevel"), reason=s(minLength=1, maxLength=300),
                                       pauseDays=i(minimum=RM["pauseDays"]["min"], maximum=RM["pauseDays"]["max"], description="required when level is paused")),
                                  ["expectedVersion", "level", "reason"], RM["reasons"]["note"])
S["Rider"]["properties"]["moderation"] = {"allOf": [ref("RiderModeration")], "description": "v0.18.29: the rider's moderation level (rider and admin views)."}
op("post", "/admin/riders/{riderId}/moderation", "adminModerateRider", "Warn, pause, ban or clear a rider", ["admin"], "Admin · People",
   params=[pref("RiderId")], body="RiderModerationCommand", ok=(200, "Rider"), mutation=True, permission="riders.block", permission_v050="riders.edit",
   desc=RM["note"] + " " + RM["levels"]["paused"] + ". " + RM["statusCommand"])


# ---- v0.18.29 A2: Add money to wallet (owner G12 Q5 + Q-D, build-spec Q1/Q2; contract.json#walletCredit)
WC = C["walletCredit"]
S["WalletCreditCommand"] = obj({"amount": ref("Money"), "reason": s(minLength=1, maxLength=WC["reasonMax"])}, ["amount", "reason"], WC["note"])
S["CountryRules"]["properties"]["walletCreditMax"] = {"allOf": [ref("Money")], "description": "v0.18.29 (owner A2-1): the largest single Add money to wallet for riders of this country, in its currency; read from the country Standard only (a zone's own value is ignored). Default " + ", ".join(f"{k} {v['amountMinor']} {v['currency']}" for k, v in WC["defaultMax"].items()) + " (minor units)."}
op("post", "/admin/riders/{riderId}/wallet-credit", "adminCreditRiderWallet", "Add money to a rider's wallet", ["admin"], "Admin · People",
   params=[pref("RiderId")], body="WalletCreditCommand", ok=(200, "Rider"), mutation=True, permission="finance.edit", permission_v050="finance.edit", desc=WC["note"])

# ---- v0.18.29 A2: payouts Automatic / Manual per country + approve a run (owner build-spec Q4; contract.json#payoutMode)
PM = C["payoutMode"]
S["CountryRules"]["properties"]["payoutMode"] = s(PM["note"], enum=PM["values"])
S["PayoutRunApproveCommand"] = obj({"country": s(pattern="^[A-Z]{2}$"), "periodEnd": ref("Timestamp"), "reason": s("v0.18.29 (owner A2-3): why the run is approved; kept in the audit.", minLength=1, maxLength=300)}, ["country", "periodEnd", "reason"])
S["PayoutRunApproved"] = obj({"country": s(), "periodEnd": ref("Timestamp"), "approved": i(minimum=0), "total": arr(ref("Money"))}, ["country", "periodEnd", "approved", "total"])
op("post", "/admin/payouts/runs/approve", "adminApprovePayoutRun", "Approve a manual payout run", ["admin"], "Admin · Finance",
   body="PayoutRunApproveCommand", ok=(200, "PayoutRunApproved"), mutation=True, permission="finance.edit", permission_v050="finance.edit", desc=PM["note"])

# ---- v0.18.29 fix job 0 (owner A2-2): Mark as paid on an owed fee (contract.json#outstandingFee.adminMarkPaid)
OMP = C["outstandingFee"]["adminMarkPaid"]
S["RiderFeeMarkPaidCommand"] = obj({"reason": s(minLength=1, maxLength=OMP["reasonMax"])}, ["reason"], OMP["note"])
op("post", "/admin/riders/{riderId}/fees/{tripId}/mark-paid", "adminMarkRiderFeePaid", "Mark a rider's owed fee as paid", ["admin"], "Admin · People",
   params=[pref("RiderId"), pref("TripId")], body="RiderFeeMarkPaidCommand", ok=(200, "Rider"), mutation=True, permission="finance.edit", permission_v050="finance.edit", desc=OMP["note"])

doc = OrderedDict()
doc["openapi"] = "3.1.0"
doc["info"] = {
    "title": "Movera API",
    "version": C["version"],
    "description": (
        "**Proposed contract — no backend exists yet.** One future backend serves the Rider (Flutter), Driver (Flutter) and "
        "Admin (React/TS) apps. Source of truth for names, enums, transitions, realtime and errors is `contract.json` + "
        "`CONTRACT.md` v" + C["version"] + " in this folder; this file must agree with them.\n\n"
        "Wire rules: ids match `" + ID_PATTERN + "`; times are RFC 3339 UTC with `Z`; durations are integer seconds; money is "
        "`Money {amountMinor, currency}`; keys camelCase, enum values snake_case. Success responses are the bare resource; errors are `Error`.\n\n"
        "Every mutation needs `Idempotency-Key`. Trip, offer, driver, rider, vehicle and config commands send `expectedVersion`; a stale "
        "version is `409 version_mismatch` and a command not allowed from the current status is `409 invalid_transition`, both with the current "
        "`projection`.\n\n"
        "Extensions: `x-actor` = actors allowed (derived from the token); `x-transition` = contract.json transition command; "
        "`x-permission` = admin permission (AdminPermission, v0.5.1); `x-permission-v050` = the v0.5.0 value it replaced; `x-permission-by-doc` = the permission per config document; "
        "`x-read-only` = a POST that changes nothing and takes no Idempotency-Key (v0.5.1); `x-server-only` = a document the apps never get; `x-terminal` on TripStatus = terminal set.\n\n"
        "Auth: bearer JWT. Actor (rider|driver|admin), subject id, zone scope and admin role/permissions come from the token, never from the body. "
        "Token issuance: the Auth tag (v0.5.0, contract.json#auth): phone + SMS code, Apple / Google, refresh rotation; test numbers accept a fixed code outside production. "
        "Admin: the Admin · Auth tag (v0.5.1, contract.json#auth.admin): e-mail and password, a one-time setup link, refresh rotation."),
}
doc["servers"] = [{"url": "https://api.dev.movera.invalid/api/v1", "description": "Placeholder; no backend exists."}]
doc["security"] = [{"bearerAuth": []}]
doc["tags"] = [{"name": t, **({"description": TAG_DESC[t]} if t in TAG_DESC else {})} for t in TAGS]
doc["x-contract"] = {"name": C["contract"], "version": C["version"], "source": "contract.json"}
doc["paths"] = PATHS
doc["components"] = OrderedDict([
    ("securitySchemes", {"bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT",
                                        "description": "Claims: sub, actor (rider|driver|admin), zoneIds, role, permissions."}}),
    ("parameters", PARAMS), ("responses", RESP), ("schemas", S)])

# v0.18.22 admin live updates (CONTRACT.md §46, contract.json#adminLiveEvents): one admin event stream.
ALE = C["adminLiveEvents"]
S["AdminLiveEventType"] = s("v0.18.22: what changed; the panel reads the record again with the normal routes.", enum=list(ALE["types"].keys()))
S["AdminLiveEvent"] = obj({"sequence": i(minimum=1), "type": ref("AdminLiveEventType"), "entityId": ref("Id"),
                           "zoneId": {"oneOf": [ref("Id"), {"type": "null"}]}, "occurredAt": ref("Timestamp"), "serverTime": ref("Timestamp")},
                          ALE["envelope"], ALE["note"])
S["AdminLiveEventPage"] = obj({"items": arr(ref("AdminLiveEvent")), "nextCursor": {"type": ["string", "null"]}}, ["items", "nextCursor"])
op("get", ALE["path"], "adminStreamEvents", "Admin live updates (what changed, in the admin's zones)", ["admin"], "Realtime",
   params=[pref("ZoneIdQuery"), q("zoneIds", {"type": "string"}, "Several zones, comma separated (inside the admin's zones)."),
           q("country", {"type": "string", "pattern": "^[A-Z]{2}$"}, "Every zone of that country the admin covers."),
           pref("After"), pref("Limit"), pref("LastEventId")],
   content=sse("Server-sent events. " + ALE["transport"] + " " + " ".join(ALE["scope"]) + " " + ALE["replay"], "AdminLiveEvent", "AdminLiveEventPage"),
   permission=ALE["permission"])

# v0.18.25 admin real app preview (CONTRACT.md §48, contract.json#previewSession): a read-only preview token for the real apps.
PVS = C["previewSession"]
S["PreviewRole"] = s("v0.18.25: which real app the preview opens.", enum=PVS["roles"])
S["PreviewSessionRequest"] = obj({"role": ref("PreviewRole"), "zoneId": ref("Id"), "useDraft": b("true: the app shows the zone's saved draft settings (GET .../config?draft=1).")},
                                 ["role", "zoneId"], PVS["note"])
S["PreviewSession"] = obj({"token": s(PVS["token"]), "role": ref("PreviewRole"), "zoneId": ref("Id"), "useDraft": b(),
                           "expiresAt": ref("Timestamp"), "subjectId": s("preview:<role>:<zoneId>")},
                          PVS["response"], PVS["handoff"] + " " + " ".join(PVS["rules"]))
op("post", PVS["path"], "adminCreatePreviewSession", "Open a read-only preview of the real rider or driver app", ["admin"], "Config",
   body="PreviewSessionRequest", ok=(201, "PreviewSession"), permission=PVS["permission"],
   desc=" ".join(PVS["rules"]))
for _p in ["/rider/config", "/driver/config"]:
    for _m in PATHS[_p].values():
        _m["parameters"].insert(0, q("draft", {"type": "string", "enum": ["0", "1"]}, "v0.18.25: '1' with a preview token (contract.json#previewSession) returns the zone's saved draft; ignored for every other token."))
# v0.18.26 phone data to the server (CONTRACT.md §49, contract.json#phoneDataToServer; BASE B13, owner 2026-11-03).
PDS = C["phoneDataToServer"]
RP, DP, EC = PDS["riderPlaces"], PDS["driverPreferences"], PDS["driverEmergencyContacts"]
S["SavedPlaceAddress"] = obj({"address": s(minLength=1, maxLength=512), "lat": n(minimum=-90, maximum=90), "lng": n(minimum=-180, maximum=180)},
                             ["address"], "v0.18.26: " + RP["place"])
_SP = OrderedDict([("label", s(minLength=1, maxLength=80)), ("kind", s(RP["kinds"], enum=["home", "work", "other"])),
                   ("type", s("v0.18.26: the app's word for an other place (gym, mall, ...).", pattern="^[a-z][a-z0-9_-]{0,31}$")),
                   ("place", ref("SavedPlaceAddress"))])
S["SavedPlace"] = obj(OrderedDict([("placeId", ref("Id"))] + list(_SP.items()) + [("createdAt", ref("Timestamp")), ("updatedAt", ref("Timestamp"))]),
                      ["placeId", "label", "kind", "place", "createdAt", "updatedAt"], "v0.18.26: one of the rider's saved places. " + PDS["privacy"])
S["SavedPlaceRequest"] = obj(_SP, ["label", "kind", "place"], "v0.18.26: " + RP["kinds"])
S["SavedPlaceImport"] = obj({"items": arr(ref("SavedPlaceRequest"), maxItems=C["countryLimits"]["ranges"]["savedPlacesPerPerson"][1])}, ["items"], "v0.18.26: " + RP["import"])
for _o in PATHS["/rider/places"].values(): _o["description"] = "v0.18.26: " + RP["routes"] + " " + RP["tooMany"] + " " + PDS["privacy"]
PATHS["/rider/places/{placeId}"]["delete"]["description"] = "v0.18.26: only the rider's own place (else 404 place_not_found)."
op("put", "/rider/places/{placeId}", "updateSavedPlace", "Change a saved place", ["rider"], "Rider · Account",
   params=[pref("PlaceId")], body="SavedPlaceRequest", ok=(200, "SavedPlace"), mutation=True,
   desc="v0.18.26: only the rider's own place (else 404 place_not_found). " + RP["kinds"])
op("post", "/rider/places/import", "importSavedPlaces", "Upload the phone's saved places once", ["rider"], "Rider · Account",
   body="SavedPlaceImport", ok=(200, "SavedPlacePage"), mutation=True, desc="v0.18.26: " + RP["import"])
S["DriverPreferences"] = obj({"categoriesOff": arr(ref("CategoryId"), uniqueItems=True, description=DP["categoriesOff"]),
                              "updatedAt": {"oneOf": [ref("Timestamp"), {"type": "null"}], "description": DP["updatedAt"]}},
                             ["categoriesOff", "updatedAt"], "v0.18.26: " + DP["dispatch"])
S["DriverPreferencesUpdate"] = obj({"categoriesOff": arr(ref("CategoryId"), uniqueItems=True, maxItems=50, description=DP["categoriesOff"])}, ["categoriesOff"])
op("get", "/driver/preferences", "getDriverPreferences", "Own ride preferences", ["driver"], "Driver · Account",
   ok=(200, "DriverPreferences"), desc="v0.18.26: " + DP["routes"])
op("put", "/driver/preferences", "putDriverPreferences", "Save own ride preferences", ["driver"], "Driver · Account",
   body="DriverPreferencesUpdate", ok=(200, "DriverPreferences"), mutation=True, desc="v0.18.26: " + DP["dispatch"])
S["EmergencyContact"] = obj({"name": s(minLength=1, maxLength=80), "phone": s(pattern=r"^\+?[0-9]{3,15}$"), "relation": s(maxLength=40)},
                            ["name", "phone"], "v0.18.26: " + EC["item"])
S["EmergencyContactList"] = obj({"items": arr(ref("EmergencyContact"), maxItems=C["countryLimits"]["ranges"]["emergencyContactsPerPerson"][1]),
                                 "updatedAt": {"oneOf": [ref("Timestamp"), {"type": "null"}], "description": EC["updatedAt"]}}, ["items", "updatedAt"])
S["EmergencyContactListUpdate"] = obj({"items": arr(ref("EmergencyContact"), maxItems=C["countryLimits"]["ranges"]["emergencyContactsPerPerson"][1])}, ["items"], EC["tooMany"])
op("get", "/driver/emergency-contacts", "getDriverEmergencyContacts", "Own emergency contacts", ["driver"], "Driver · Account",
   ok=(200, "EmergencyContactList"), desc="v0.18.26: " + EC["routes"] + " " + PDS["privacy"])
op("put", "/driver/emergency-contacts", "putDriverEmergencyContacts", "Save own emergency contacts", ["driver"], "Driver · Account",
   body="EmergencyContactListUpdate", ok=(200, "EmergencyContactList"), mutation=True, desc="v0.18.26: " + EC["routes"] + " " + EC["tooMany"])
S["IncidentEmergencyContacts"] = obj({"incidentId": ref("Id"), "driverId": {"oneOf": [ref("Id"), {"type": "null"}]},
                                      "items": arr(ref("EmergencyContact")), "updatedAt": {"oneOf": [ref("Timestamp"), {"type": "null"}]},
                                      "rider": {"oneOf": [obj({"riderId": ref("Id"), "items": arr(ref("EmergencyContact")), "updatedAt": {"oneOf": [ref("Timestamp"), {"type": "null"}]}}, ["riderId", "items", "updatedAt"]), {"type": "null"}]}},
                                     ["incidentId", "driverId", "items", "updatedAt", "rider"], "v0.18.26: " + PDS["admin"]["emergencyContacts"])
op("get", "/admin/incidents/{incidentId}/emergency-contacts", "adminIncidentEmergencyContacts", "The incident driver's emergency contacts (read-only, audited)",
   ["admin"], "Admin · Safety", params=[pref("IncidentId")], ok=(200, "IncidentEmergencyContacts"), permission="incidents.read",
   desc="v0.18.26: " + PDS["admin"]["emergencyContacts"])
S["AdminRiderSavedPlaces"] = obj({"riderId": ref("Id"), "items": arr(ref("SavedPlace"))}, ["riderId", "items"], "v0.18.26: " + PDS["admin"]["riderPlaces"])
op("get", "/admin/riders/{riderId}/saved-places", "adminRiderSavedPlaces", "A rider's saved places (read-only, audited)", ["admin"], "Admin · People",
   params=[pref("RiderId")], ok=(200, "AdminRiderSavedPlaces"), permission="riders.read", desc="v0.18.26: " + PDS["admin"]["riderPlaces"])
S["AdminDriverPreferences"] = obj({"driverId": ref("Id"), "categoriesOff": arr(ref("CategoryId")), "updatedAt": {"oneOf": [ref("Timestamp"), {"type": "null"}]}},
                                  ["driverId", "categoriesOff", "updatedAt"], "v0.18.26: " + PDS["admin"]["driverPreferences"])
op("get", "/admin/drivers/{driverId}/preferences", "adminDriverPreferences", "A driver's ride preferences (read-only, audited)", ["admin"], "Admin · People",
   params=[pref("DriverId")], ok=(200, "AdminDriverPreferences"), permission="drivers.read", desc="v0.18.26: " + PDS["admin"]["driverPreferences"])

REC = PDS["riderEmergencyContacts"]
op("get", "/rider/emergency-contacts", "getRiderEmergencyContacts", "Own emergency contacts", ["rider"], "Rider · Account",
   ok=(200, "EmergencyContactList"), desc="v0.18.26: " + REC["note"] + " " + REC["routes"] + " " + PDS["privacy"])
op("put", "/rider/emergency-contacts", "putRiderEmergencyContacts", "Save own emergency contacts", ["rider"], "Rider · Account",
   body="EmergencyContactListUpdate", ok=(200, "EmergencyContactList"), mutation=True, desc="v0.18.26: " + REC["routes"])

# v0.18.33 (fix job 5, contract.json#afterTestRules): booked ride next for an on-trip driver; wallet first per ride.
ATR = C["afterTestRules"]
S["DispatchDocument"]["properties"]["bookedNext"] = obj({"on": {**b(), "default": C["configDefaults"]["dispatch"]["zone"]["bookedNext"]["on"]},
                                                         "withinMin": {**i(minimum=0, maximum=240), "default": C["configDefaults"]["dispatch"]["zone"]["bookedNext"]["withinMin"]}},
                                                        ["on", "withinMin"], "v0.18.33: " + ATR["bookedNext"]["rule"] + " " + ATR["bookedNext"]["settings"])
S["CreateTripRequest"]["properties"]["walletFirst"] = {**b("v0.18.33: " + ATR["walletFirst"]["rule"]), "default": True}
S["TripProjection"]["properties"]["walletFirst"] = b("v0.18.33: " + ATR["walletFirst"]["projection"])
S["CountryRules"]["properties"]["onTripOffers"] = obj({"minRouteDonePct": {**i(minimum=0, maximum=100), "default": C["configDefaults"]["onTripOffers"]["minRouteDonePct"]},
                                                       "lateFreeCancelMin": {**i(ATR["onTripOffers"]["lateFreeCancel"], minimum=0, maximum=120), "default": C["configDefaults"]["onTripOffers"]["lateFreeCancelMin"]}}, ["minRouteDonePct"],
                                                       "v0.18.33: " + ATR["bookedNext"]["rule"] + " " + ATR["onTripOffers"]["settings"])
S["TripProjection"]["properties"]["chain"] = obj({"queued": b("Still queued behind the driver's current trip (cancel free)."), "freeCancelAt": ref("Timestamp")}, ["queued"], "v0.18.33 (owner Q3 + Q5), all views: a trip a driver on a trip took next. " + ATR["onTripOffers"]["lateFreeCancel"])
S["TripProjection"]["properties"]["nextAfterTripId"] = {"allOf": [ref("Id")], "description": "v0.18.33, driver and admin views: a live trip queued behind this driver's current trip (contract.json#afterTestRules.bookedNext.accept)."}
S["RiderAppConfig"]["properties"]["wallet"] = obj({"usedFirst": {**b("The balance (one per currency, no conversion) pays first. v0.18.33: " + ATR["walletFirst"]["zone"]), "default": True}})
