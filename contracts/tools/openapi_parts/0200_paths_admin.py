# Split from tools/gen_openapi.py (rule 25, no behaviour change): run by it in name order with its globals.
# ---- Admin
ZF = [pref("ListZoneId"), pref("ListZoneIds"), pref("ListCountry")]
ZF_DESC = " v0.17.2 (contract.json#adminListFilters): zoneId, zoneIds and country narrow the list inside those zones; an unknown query key → 400 invalid_request (reason unknown_filter)."
AL = [pref("Cursor"), pref("Limit")]
lists = {
    "trips": ("TripProjectionPage", "trips.read", [q("status", ref("TripStatus"), multi=True), q("kind", ref("TripKind")), *ZF,
              q("categoryId", ref("CategoryId")), q("riderId", ref("Id")), q("driverId", ref("Id")), q("paymentStatus", ref("PaymentStatus")),
              pref("From"), pref("To"), pref("Q")]),
    "riders": ("RiderPage", "riders.read", [q("status", {"type": "string", "enum": ["active", "suspended"]}), *ZF, pref("Q")]),
    "drivers": ("DriverPage", "drivers.read", [q("accountStatus", ref("DriverAccountStatus"), multi=True),
                q("onlineStatus", ref("DriverOnlineStatus"), multi=True), *ZF, q("categoryId", ref("CategoryId")), pref("Q")]),
    "fleets": ("FleetPage", "drivers.read", [q("status", ref("FleetStatus"), multi=True), q("country", ref("DriverCountry")), pref("ZoneIdQuery"), pref("Q")]),
    "vehicles": ("VehiclePage", "drivers.read", [q("status", ref("VehicleStatus"), multi=True), q("driverId", ref("Id")), q("fleetId", ref("Id")),
                 q("categoryId", ref("CategoryId")), pref("Q")]),
    "payments": ("PaymentIntentPage", "finance.read", [q("status", ref("PaymentStatus"), multi=True), q("method", ref("PaymentMethod")),
                 q("tripId", ref("Id")), q("riderId", ref("Id")), *ZF, pref("From"), pref("To")]),
    "refunds": ("RefundPage", "finance.read", [q("status", ref("RefundStatus"), multi=True), q("paymentId", ref("Id")), q("tripId", ref("Id")),
                pref("From"), pref("To"), *ZF]),
    "payouts": ("PayoutPage", "finance.read", [q("status", {"type": "string", "enum": ["pending", "pending_approval", "paid", "failed", "held"]}, multi=True),
                q("driverId", ref("Id")), pref("From"), pref("To"), *ZF]),
    "tickets": ("SupportTicketPage", "support.reply", [q("status", {"type": "string", "enum": ["open", "pending", "resolved", "closed"]}, multi=True),
                q("priority", {"type": "string", "enum": ["low", "normal", "high", "urgent"]}), q("tripId", ref("Id")),
                q("riderId", ref("Id")), q("driverId", ref("Id")), pref("Q"), *ZF,
                q("assignedTo", s("v0.18.15: me, none or an admin id."))]),
    "incidents": ("IncidentPage", "incidents.read", [q("status", {"type": "string", "enum": ["open", "investigating", "resolved", "dismissed"]}, multi=True),
                  q("severity", {"type": "string", "enum": ["low", "medium", "high", "critical"]}), q("kind", {"type": "string"}),
                  q("tripId", ref("Id")), *ZF, pref("From"), pref("To")]),
}
PERM_V050 = {"vehicles": "fleet.read", "payments": "payments.read", "refunds": "payments.read", "payouts": "payments.read",
             "tickets": "support.read", "incidents": "safety.read"}
ZF_LISTS = {"trips", "riders", "drivers", "payments", "refunds", "payouts", "tickets", "incidents"}
for name, (page, perm, filt) in lists.items():
    op("get", f"/admin/{name}", f"adminList{name.capitalize()}", f"List {name} (cursor paging)", ["admin"], "Admin · Lists",
       params=AL + filt, ok=(200, page), permission=perm, permission_v050=PERM_V050.get(name),
       desc="Results are limited to the zones in the admin's token scope." + (ZF_DESC if name in ZF_LISTS else ""))
S["WaitlistEntryPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("WaitlistEntry"))}}], "description": "Page<WaitlistEntry>"}
op("get", "/admin/waitlist", "adminListWaitlist", "The sign-in waiting list (newest first)", ["admin"], "Admin · Lists",
   params=AL + [q("app", {"type": "string", "enum": ["rider", "driver"]})], ok=(200, "WaitlistEntryPage"), permission="overview.read",
   desc="v0.15.0 (owner 2026-10-29, decision 5): the numbers that asked to join, newest lastAt first; the admin page reads it again every 15 s. " + AU["waitlist"]["admin"])
# v0.16.0 (owner 2026-10-29): Crashes & errors (contract.json#telemetry.errorGroups).
S["ErrorGroupPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("ErrorGroup"))}}], "description": "Page<ErrorGroup>"}
op("get", "/admin/errors", "adminListErrors", "Crashes & errors, grouped (newest first)", ["admin"], "Admin · System",
   params=AL + [q("app", s(enum=TE["apps"])), q("platform", s(enum=TE["platforms"])), q("version", s(), "An app version the group was seen in."),
                q("status", s(enum=TE["statuses"]))], ok=(200, "ErrorGroupPage"),
   desc="v0.16.0: " + TE["fingerprint"] + ". " + TE["admin"] + " Permission: " + TE["permission"] + ".")
op("patch", "/admin/errors/{errorId}", "adminSetErrorStatus", "Mark a crash or error group fixed (or open)", ["admin"], "Admin · System",
   params=[pref("ErrorId")], body="ErrorGroupStatusCommand", ok=(200, "ErrorGroup"), mutation=True,
   desc="v0.16.0: " + TE["reopen"] + ". Audited. Permission: " + TE["permission"] + ".")
op("get", "/admin/trips/{tripId}", "adminGetTrip", "Trip detail incl. money split", ["admin"], "Admin · Trips",
   params=TID, ok=(200, TP), permission="trips.read")
for seg, cmd, opid, body, summ, perm, appr, okc in [
        ("cancel", "cancel", "adminCancelTrip", "AdminCancelCommand", "Cancel any non-terminal trip", "trips.intervene", False, (200, TP)),
        ("reassign", "reassign", "adminReassignTrip", "AdminReassignCommand", "Take the trip from its driver, back to searching", "trips.intervene", False, (200, TP)),
        ("assign", "assign", "adminAssignTrip", "AdminAssignCommand", "Direct assign: exclusive offer to one driver (Assigned by Movera)", "trips.intervene", False, (200, TP)),
        ("radar-group", "assign", "adminSendRadarGroup", "AdminRadarGroupCommand", "Send the trip to a radar group of up to 10 drivers", "trips.intervene", False, (200, "AdminRadarGroup")),
        ("no-show", "no_show", "adminMarkNoShow", "AdminNoShowCommand", "Mark rider no-show", "trips.intervene", False, (200, TP)),
        ("complete", "complete", "adminCompleteTrip", "AdminCompleteCommand", "Force-complete a stuck onboard trip", "trips.intervene", False, (200, TP)),
        ("refund", None, "adminRefundTrip", "AdminRefundCommand", "Refund (full or partial)", "payments.refund", True, (201, "Refund")),
        ("adjust", None, "adminAdjustTrip", "AdminAdjustCommand", "Adjust fare / waiting / waive cancel fee", "trips.intervene", True, (200, TP)),
        ("driver-bonus", None, "adminAddDriverBonus", "AdminDriverBonusCommand", "Add money to the trip for the driver (paid by Movera)", "trips.intervene", False, (200, TP))]:
    op("post", f"/admin/trips/{{tripId}}/{seg}", opid, summ, ["admin"], "Admin · Trips", params=TID, body=body, ok=okc,
       mutation=True, transition=cmd, approval=appr, permission=perm, permission_v050="payments.edit" if seg == "refund" else "trips.edit",
       desc=(None if cmd else "Not a lifecycle transition (status unchanged; paymentStatus/fare change and emit payment_updated / trip_projection).")
            if not appr else ("Not a lifecycle transition (status unchanged; paymentStatus/fare change and emit payment_updated / trip_projection). " if not cmd else "")
            + "v0.7.2 (owner 2026-10-28, one admin is enough): 200 / 201 at once for every admin with the permission, written in the audit.")
op("get", "/admin/trips/{tripId}/offers", "adminListTripOffers", "Offers of a trip (who has it, countdown)", ["admin"], "Admin · Dispatch",
   params=TID + AL, ok=(200, "OfferPage"), permission="trips.read")
op("get", "/admin/trips/{tripId}/nearby-drivers", "adminNearbyDrivers", "Active drivers near the trip's pickup", ["admin"], "Admin · Dispatch",
   params=TID + [q("scope", {"type": "string", "enum": C["adminDispatch"]["nearbyScopes"], "default": "radius"}),
                 q("radiusKm", {"type": "number", "minimum": 0.1, "maximum": 100,
                                "examples": C["adminDispatch"]["nearbyRadiusPresetsKm"]}, "Presets 5 / 7 / 10 km or any number (scope=radius).")],
   ok=(200, "NearbyDriverList"), permission="trips.read")
op("get", "/admin/dispatch/stream", "adminStreamDispatch", "Admin dispatch feed (offers, lock, driver bonus)", ["admin"], "Realtime",
   params=[pref("ZoneIdQuery"), pref("After"), pref("LastEventId")], content=sse("Server-sent events.", "AdminDispatchEvent", "AdminDispatchEventPage"),
   permission="trips.read")
# ---- v0.9.0 (CONTRACT.md §18): real data for the admin
op("post", "/admin/payouts", "adminCreatePayout", "Create payout by hand (driver + date range)", ["admin"], "Admin · Money",
   body="PayoutCreateCommand", ok=(201, "Payout"), mutation=True, permission="finance.edit",
   desc="v0.9.0. Same calculation as the weekly job; trips already in a payout are never counted again. 409 nothing_to_pay when no trip is left.")
op("post", "/admin/payouts/{payoutId}/paid", "adminMarkPayoutPaid", "Mark a payout as paid", ["admin"], "Admin · Money",
   params=[pref("PayoutId")], body="PayoutPaidCommand", ok=(200, "Payout"), mutation=True, permission="finance.edit", desc="v0.9.0. 409 invalid_transition when it is already paid.")
op("get", "/support/tickets/{ticketId}", "getOwnTicket", "One own support ticket with its messages", ["rider", "driver"], "Support",
   params=[pref("TicketId")], ok=(200, "SupportTicket"), desc="v0.9.0.")
op("get", "/admin/tickets/{ticketId}", "adminGetTicket", "A support ticket with its messages", ["admin"], "Admin · Support",
   params=[pref("TicketId")], ok=(200, "SupportTicket"), permission="support.reply", desc="v0.9.0. In the admin's zones only (else 403 zone_out_of_scope). v0.13.0: support.reply is needed to read too.")
op("post", "/admin/tickets/{ticketId}/reply", "adminReplyTicket", "Answer a support ticket", ["admin"], "Admin · Support",
   params=[pref("TicketId")], body="TicketReplyCommand", ok=(200, "SupportTicket"), mutation=True, permission="support.reply",
   desc="v0.9.0. The person sees the answer in the app (GET /support/tickets/{ticketId}). v0.13.0: the admin's zones only (else 403 zone_out_of_scope); audited. v0.18.53 (§75): the ticket's owner gets a push at once (kind support_reply, contract.json#support.answerPush), whatever the rider's Ride updates switch.")
# v0.18.15 support desk (contract.json#supportDesk)
op("post", "/support/tickets/{ticketId}/messages", "writeOwnTicket", "Write on an own support ticket", ["rider", "driver"], "Support",
   params=[pref("TicketId")], body="TicketPersonMessage", ok=(201, "SupportTicket"), mutation=True,
   desc="v0.18.15 (owner QO-1, chat-style): the status becomes open. A solved or closed ticket takes no more messages (owner: \"Can't write\"): 409 invalid_transition, reason ticket_solved or ticket_closed.")
op("post", "/support/tickets/{ticketId}/feedback", "giveTicketFeedback", "Comment on a solved ticket", ["rider", "driver"], "Support",
   params=[pref("TicketId")], body="TicketFeedback", ok=(201, "SupportTicket"), mutation=True, desc="v0.18.15. " + SD["feedback"])
op("get", "/support/topics", "listSupportTopics", "Ticket topics that are on", ["rider", "driver"], "Support", ok=(200, "SupportTopics"), desc="v0.18.15 (owner QO-4).")
for verb, body, summary, d in [("claim", "EmptyCommand", "Claim a ticket", SD["adminCommands"]["claim"]), ("leave", "EmptyCommand", "Leave a claimed ticket", SD["adminCommands"]["leave"]), ("assign", "TicketAssignCommand", "Assign a ticket", SD["adminCommands"]["assign"]),
                               ("topic", "TicketTopicCommand", "Change a ticket's topic", SD["adminCommands"]["topic"]), ("waiting", "TicketWaitingCommand", "Mark waiting for the person", SD["adminCommands"]["waiting"]),
                               ("solve", "TicketSolveCommand", "Solve a ticket", SD["adminCommands"]["solve"]), ("reopen", "TicketReasonCommand", "Reopen a ticket", SD["adminCommands"]["reopen"]),
                               ("case", "TicketReasonCommand", "Open a safety case from a ticket", SD["adminCommands"]["case"])]:
    op("post", f"/admin/tickets/{{ticketId}}/{verb}", f"adminTicket{verb.capitalize()}", summary, ["admin"], "Admin · Support",
       params=[pref("TicketId")], body=body, ok=(200, "SupportTicket"), mutation=True, permission="support.reply", desc="v0.18.15. " + d + " The admin's zones only (else 403 zone_out_of_scope).")
op("get", "/admin/support/settings", "adminGetSupportSettings", "Support settings of a country", ["admin"], "Admin · Support",
   params=[q("country", s(enum=SD["settings"]["countries"]))], ok=(200, "SupportSettings"), permission="support.reply", desc="v0.18.15. " + SD["settings"]["endpoints"])
op("put", "/admin/support/settings", "adminPutSupportSettings", "Save the support settings of a country", ["admin"], "Admin · Support",
   body="SupportSettings", ok=(200, "SupportSettings"), mutation=True, permission="settings.edit", desc="v0.18.15. " + SD["settings"]["limits"])

# v0.18.15 alert desk (contract.json#alertDesk)
AID = {"name": "alertId", "in": "path", "required": True, "schema": s(pattern="^[A-Za-z0-9_:.-]{1,200}$")}
KIND = {"name": "kind", "in": "path", "required": True, "schema": s(pattern="^[a-z][a-z0-9_]{0,63}$")}
op("get", "/admin/alerts/book", "adminAlertBook", "Who works on each alert, mutes, quiet hours, settings and rules", ["admin"], "Admin · Alerts", params=[q("country", s(enum=C["supportDesk"]["settings"]["countries"]))], ok=(200, "AlertBookState"), permission="overview.read", desc="v0.18.15. " + AD["book"])
for verb, body in [("take", "AlertTakeCommand"), ("done", "AlertDoneCommand"), ("snooze", "AlertSnoozeCommand"), ("pass", "AlertPassCommand")]:
    op("post", f"/admin/alerts/{{alertId}}/{verb}", f"adminAlert{verb.capitalize()}", f"Alert: {verb}", ["admin"], "Admin · Alerts", params=[AID], body=body, ok=(200, "AlertBookState"), mutation=True, permission="overview.read", desc="v0.18.15. " + AD["commands"][verb] + " " + AD["permissions"]["note"])
op("put", "/admin/alerts/mutes/{kind}", "adminAlertMute", "Mute a kind of alert", ["admin"], "Admin · Alerts", params=[KIND, q("country", s(enum=C["supportDesk"]["settings"]["countries"]))], body="AlertMuteCommand", ok=(200, "AlertBookState"), mutation=True, permission="alerts.manage", desc="v0.18.15. " + AD["commands"]["mute"])
op("delete", "/admin/alerts/mutes/{kind}", "adminAlertUnmute", "Unmute a kind of alert", ["admin"], "Admin · Alerts", params=[KIND, q("country", s(enum=C["supportDesk"]["settings"]["countries"]))], ok=(200, "AlertBookState"), mutation=True, permission="alerts.manage", desc="v0.18.15.")
op("put", "/admin/alerts/quiet", "adminAlertQuiet", "My quiet hours", ["admin"], "Admin · Alerts", params=[q("country", s(enum=C["supportDesk"]["settings"]["countries"]))], body="AlertQuietCommand", ok=(200, "AlertBookState"), mutation=True, permission="overview.read", desc="v0.18.15. " + AD["commands"]["quiet"])
op("put", "/admin/alerts/settings", "adminAlertSettings", "Save the alert settings", ["admin"], "Admin · Alerts", body="AlertSettingsCommand", ok=(200, "AlertBookState"), mutation=True, permission="alerts.manage", desc="v0.18.15. " + AD["commands"]["settings"])
op("put", "/admin/alerts/rules", "adminAlertRules", "Save the alert rules", ["admin"], "Admin · Alerts", body="AlertRulesCommand", ok=(200, "AlertBookState"), mutation=True, permission="alerts.manage", desc="v0.18.15. " + AD["commands"]["rules"])
op("get", "/admin/alerts/history", "adminAlertHistory", "Alert history for the export", ["admin"], "Admin · Alerts", params=[q("country", s(enum=C["supportDesk"]["settings"]["countries"])), pref("From"), pref("To")], ok=(200, "AlertHistory"), permission="overview.read", desc="v0.18.15. " + AD["commands"]["export"])

# v0.18.15 incidents (contract.json#incidentDesk)
op("get", "/admin/incidents/settings", "adminIncidentSettings", "Incident settings", ["admin"], "Admin · Safety", params=[q("country", s(enum=C["supportDesk"]["settings"]["countries"]))], ok=(200, "IncidentSettingsDoc"), permission="incidents.read", desc="v0.18.15. " + ID_["settings"])
op("put", "/admin/incidents/settings", "adminPutIncidentSettings", "Save the incident settings", ["admin"], "Admin · Safety", body="IncidentSettingsCommand", ok=(200, "IncidentSettingsDoc"), mutation=True, permission="safety.edit", desc="v0.18.15.")
op("post", "/admin/incidents/{incidentId}/report", "adminIncidentReport", "Record a case report download", ["admin"], "Admin · Safety", params=[pref("IncidentId")], body="EmptyCommand", ok=(204, None), mutation=True, permission="incidents.read", desc="v0.18.15. " + ID_["report"])

# v0.18.15 review rules (contract.json#reviewRules)
op("get", "/admin/reviews/rules", "adminReviewRules", "Review rules of a country", ["admin"], "Admin · Reviews", params=[q("country", s(enum=C["supportDesk"]["settings"]["countries"]))], ok=(200, "ReviewRules"), permission="settings.read", desc="v0.18.15. " + RR["applied"])
op("put", "/admin/reviews/rules", "adminPutReviewRules", "Save the review rules of a country", ["admin"], "Admin · Reviews", body="ReviewRules", ok=(200, "ReviewRules"), mutation=True, permission="settings.edit", desc="v0.18.15. " + RR["rules"])
op("get", "/admin/reviews/queue", "adminReviewQueue", "People the review rules put up for an admin", ["admin"], "Admin · Reviews", ok=(200, "ReviewQueue"), permission="riders.read", desc="v0.18.15.")
op("post", "/admin/reviews/queue/{who}/{personId}/done", "adminReviewDone", "An admin looked at a person", ["admin"], "Admin · Reviews",
   params=[{"name": "who", "in": "path", "required": True, "schema": s(enum=["driver", "rider"])}, {"name": "personId", "in": "path", "required": True, "schema": ref("Id")}],
   body="ReviewDoneCommand", ok=(200, "ReviewQueue"), mutation=True, permission="riders.block", desc="v0.18.15.")

op("get", "/admin/ratings", "adminListRatings", "Ratings riders and drivers gave each other", ["admin"], "Admin · Reviews",
   params=AL + [q("rater", {"type": "string", "enum": ["rider", "driver"]}, "Who gave the rating."), q("hidden", {"type": "boolean"}), q("maxStars", {"type": "integer", "minimum": 1, "maximum": 5}),
                q("driverId", ref("Id")), q("riderId", ref("Id")), *ZF, pref("From"), pref("To")],
   ok=(200, "AdminRatingPage"), permission="settings.read", desc="v0.9.0. Newest first; limited to the admin's zones." + ZF_DESC)
for verb, summ in [("hide", "Hide a rating"), ("restore", "Show a hidden rating again")]:
    op("post", f"/admin/ratings/{{tripId}}/{{from}}/{verb}", f"admin{verb.capitalize()}Rating", summ, ["admin"], "Admin · Reviews",
       params=TID + [pref("RatingFrom")], body="RatingModerationCommand", ok=(200, "AdminRating"), mutation=True, permission="settings.publish",
       desc="v0.9.0. A hidden rating stops counting in the person's average and in the low-rating risk signal; restoring counts it again.")
op("get", "/admin/risk/signals", "adminRiskSignals", "Risk signals the server counts (cancels, failed payments, low rating)", ["admin"], "Admin · Safety",
   params=AL + [q("who", {"type": "string", "enum": ["driver", "rider"]}), *ZF], ok=(200, "RiskPage"), permission="safety.edit",
   desc="v0.9.0 (contract.json#risk). People with at least one counted event in the window." + ZF_DESC)
op("get", "/admin/kpis", "adminKpis", "Key numbers per zone and day", ["admin"], "Admin · Reports",
   params=[*ZF, q("fromDate", {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"}), q("toDate", {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"})],
   ok=(200, "KpiReport"), permission="overview.read",
   desc="v0.9.0 (contract.json#kpis). Days are zone-local, both ends included, at most kpis.maxDays. Today: source live; earlier: the nightly summary." + ZF_DESC)
# ---- v0.7.0 (CONTRACT.md §15): SOS and incidents
for who, path, opid in [("rider", "/rider/trips/{tripId}/sos", "riderSos"), ("driver", "/driver/trips/{tripId}/sos", "driverSos")]:
    op("post", path, opid, f"The {who} presses SOS: alert Movera", [who], "Safety", params=TID, body="SosRequest", ok=(200, "SosReceipt"), mutation=True,
       desc=f"v0.7.0. Only the trip's own {who}, while the trip is live (contract.json#safety.sos.{who}Statuses); otherwise 409 invalid_transition with the trip. "
            "Creates the trip's one open SOS incident, or returns it when one is open (a second SOS from either side). The app opens the emergency call (112) itself; "
            "it retries with the same Idempotency-Key and then shows only \"SOS sent\".")
# ---- v0.12.0 (CONTRACT.md §22): ride check answers
for who, path, opid in [("rider", "/rider/trips/{tripId}/ride-check", "riderRideCheck"), ("driver", "/driver/trips/{tripId}/ride-check", "driverRideCheck")]:
    op("post", path, opid, f"The {who} app reports a ride check (shown, or answered)", [who], "Safety", params=TID, body="RideCheckReport", ok=(200, "RideCheckReceipt"), mutation=True,
       desc=f"v0.12.0. Only the trip's own {who}, while the trip is live or up to contract.json#safety.rideCheck.completedWithinMinutes after it completed "
            f"(contract.json#safety.rideCheck.{who}Statuses); otherwise 409 invalid_transition with the trip. Without answer: the card showed; the server opens a ride_check "
            "incident without the alarm when no answer comes within noAnswerSeconds (120 s). answer ok: saved on the trip only. answer need_help: opens or joins the trip's "
            "ride_check incident with the alarm. Idempotent by checkId and by Idempotency-Key (contract.json#safety.rideCheck.idempotency).")
op("get", "/admin/incidents/stream", "adminStreamIncidents", "Admin incident feed (opened, updated, escalated, closed)", ["admin"], "Admin · Safety",
   params=[pref("After"), pref("LastEventId")], content=sse("Server-sent events.", "AdminIncidentEvent", "AdminIncidentEventPage"), permission="overview.read",
   desc="v0.7.0. Any signed-in admin may listen. Events of an incident go to admins with incidents.read whose zones cover its zone; once it is escalated "
        "(not taken in contract.json#safety.escalateAfterSeconds) to every signed-in admin. Without Accept: text/event-stream: a JSON page of the same events (polling fallback).")
op("get", "/admin/incidents/{incidentId}", "adminGetIncident", "Incident detail with the car's latest position", ["admin"], "Admin · Safety",
   params=[pref("IncidentId")], ok=(200, "Incident"), permission="incidents.read", desc="v0.7.0. In the admin's zones only (else 403 zone_out_of_scope).")
for seg, opid, summ in [("take", "adminTakeIncident", "Take the incident (New → Taken)"),
                        ("resolve", "adminResolveIncident", "Solve the incident (→ Solved)"),
                        ("dismiss", "adminDismissIncident", "Call it a false alarm (→ False alarm)")]:
    op("post", f"/admin/incidents/{{incidentId}}/{seg}", opid, summ, ["admin"], "Admin · Safety", params=[pref("IncidentId")], body="AdminIncidentCommand",
       ok=(200, "Incident"), mutation=True, permission="safety.edit",
       desc="v0.7.0 (contract.json#safety.transitions). In the admin's zones only. A status the command cannot leave → 409 invalid_transition with the incident; "
            "a stale expectedVersion → 409 version_mismatch with the incident. Written in the audit.")
op("post", "/admin/drivers/{driverId}/status", "adminSetDriverStatus", "Set driver account status", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="DriverStatusCommand", ok=(200, "Driver"), mutation=True, permission="drivers.activate", permission_v050="drivers.edit",
   desc=C["driverOnboarding"]["activation"]["note"])
op("post", "/admin/riders/{riderId}/status", "adminSetRiderStatus", "Set rider status", ["admin"], "Admin · People",
   params=[pref("RiderId")], body="RiderStatusCommand", ok=(200, "Rider"), mutation=True, permission="riders.block", permission_v050="riders.edit")
op("post", "/admin/vehicles/{vehicleId}/review", "adminReviewVehicle", "Approve / reject / block a vehicle", ["admin"], "Admin · People",
   params=[pref("VehicleId")], body="VehicleReviewCommand", ok=(200, "Vehicle"), mutation=True, permission="vehicles.edit", permission_v050="fleet.edit")
op("post", "/admin/documents/{documentId}/review", "adminReviewDocument", "Approve / reject a document", ["admin"], "Admin · People",
   params=[pref("DocumentId")], body="DocumentReviewCommand", ok=(200, "Document"), mutation=True, permission="documents.approve", permission_v050="drivers.edit",
   desc="v0.18.0: " + C["driverOnboarding"]["documentExpiry"]["note"])
# ---- v0.5.3 (CONTRACT.md §14): fleets and document files
op("get", "/admin/drivers/{driverId}", "adminGetDriver", "Driver detail (details, fleet, documents)", ["admin"], "Admin · People",
   params=[pref("DriverId")], ok=(200, "Driver"), permission="drivers.read", desc="v0.5.3.")
op("get", "/admin/fleets/{fleetId}", "adminGetFleet", "Fleet detail: company, code, drivers and cars", ["admin"], "Admin · People",
   params=[pref("FleetId")], ok=(200, "FleetView"), permission="drivers.read", desc="v0.5.3.")
op("post", "/admin/fleets/{fleetId}/review", "adminReviewFleet", "Approve / reject / block a fleet", ["admin"], "Admin · People",
   params=[pref("FleetId")], body="FleetReviewCommand", ok=(200, "Fleet"), mutation=True, permission="drivers.activate",
   desc="v0.5.3. The first approval makes the join code (contract.json#driverOnboarding.fleetCode). Approving the fleet does not activate its owner as a driver: POST /admin/drivers/{driverId}/status does, when his own documents are approved.")
op("post", "/admin/fleets/{fleetId}/code", "adminRenewFleetCode", "Make a new join code (the old one stops working)", ["admin"], "Admin · People",
   params=[pref("FleetId")], body="FleetCodeCommand", ok=(200, "Fleet"), mutation=True, permission="drivers.activate", desc="v0.5.3. Approved fleets only (409 invalid_transition).")
for seg, opid, summ in [("accept", "adminAcceptFleetInvitation", "Accept a pending invitation or request for the fleet"), ("cancel", "adminCancelFleetInvitation", "Cancel a pending invitation or request")]:
    op("post", f"/admin/fleets/{{fleetId}}/invitations/{{invitationId}}/{seg}", opid, summ, ["admin"], "Admin · People",
       params=[pref("FleetId"), pref("InvitationId")], ok=(200, "FleetInvitation"), mutation=True, permission="drivers.activate",
       desc="v0.5.3. The same effect as the driver's or owner's answer; written in the audit.")
op("post", "/admin/fleets/{fleetId}/drivers/{driverId}/remove", "adminRemoveFleetDriver", "Remove a driver from a fleet", ["admin"], "Admin · People",
   params=[pref("FleetId"), pref("DriverId")], ok=(204, None), mutation=True, permission="drivers.activate",
   desc="v0.5.3. Same effect as the owner's POST /driver/fleet/drivers/{driverId}/remove; written in the audit.")
op("get", "/admin/documents/{documentId}/file", "adminGetDocumentFile", "The uploaded file", ["admin"], "Admin · People",
   params=[pref("DocumentId")], content=FILE_CONTENT, ok=(200, None), ok_desc="The file, with its media type.", permission="documents.approve",
   desc="v0.5.3. Read in the admin's zones only; every read is written in the audit.")
op("get", "/admin/config/{doc}", "adminGetConfigDraft", "Get the config draft for a zone", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc"), pref("ConfigZoneId"), pref("ConfigCountry")], ok=(200, "ConfigDraft"), permission="settings.read", permission_v050="config.read",
   desc="pricing and dispatch (v0.5.1) are server-only documents: only admins with settings.read read them; GET /rider/config and /driver/config never include them.")
op("put", "/admin/config/{doc}", "adminPutConfigDraft", "Replace the config draft", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigDraftUpdate", ok=(200, "ConfigDraft"), mutation=True, permission="settings.edit", permission_v050="config.edit",
   ext={"x-permission-by-doc": {"rider_app_config": "settings.edit", "driver_app_config": "settings.edit", "pricing": "settings.edit", "dispatch": "dispatch.edit", "country_rules": "settings.edit", "onboarding": "settings.edit"}},
   desc="The draft's document must be the doc's schema (pricing → PricingDocument, dispatch → DispatchDocument, v0.5.1). x-permission-by-doc: the admin panel saves dispatch rules with dispatch.edit.")
op("post", "/admin/config/{doc}/publish", "adminPublishConfig", "Publish the draft at once (no second admin, v0.8.0)", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigPublishCommand", ok=(200, "ConfigPublication"), mutation=True,
   permission="settings.publish", permission_v050="config.edit",
   ext={"x-permission-by-doc": {"rider_app_config": "settings.publish", "driver_app_config": "settings.publish", "pricing": "settings.publish", "dispatch": "dispatch.edit", "country_rules": "settings.publish", "onboarding": "settings.publish"}},
   desc=C["configDocs"]["publishApproval"] + " The server stamps version and publishedAt (contract.json#configVersion). "
        "Emits config_published on the app streams for rider_app_config and driver_app_config only; pricing and dispatch (server-only) are published with the same version rule but never reach the apps.")
S["UseStandardCommand"] = obj(dict(EV, zoneId=ref("Id")), ["expectedVersion", "zoneId"], C["configDocs"]["useStandard"])
op("post", "/admin/config/{doc}/use-standard", "adminUseStandardConfig", "Go back to the country standard (v0.8.0)", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="UseStandardCommand", ok=(200, "ConfigPublication"), mutation=True, permission="settings.publish",
   ext={"x-permission-by-doc": {"rider_app_config": "settings.publish", "driver_app_config": "settings.publish", "pricing": "settings.publish", "dispatch": "dispatch.edit"}},
   desc=C["configDocs"]["useStandard"] + " The answer names the zone and the standard's new version.")
op("get", "/admin/zones/{zoneId}/surge", "adminGetSurge", "The zone's current surge schedule", ["admin"], "Admin · Config",
   params=[pref("ZoneId")], ok=(200, "SurgeSchedule"), permission="settings.read", permission_v050="pricing.read", desc="204 when the zone has none (flat ×1.0).")
PATHS["/admin/zones/{zoneId}/surge"]["get"]["responses"]["204"] = {"description": "No surge schedule", "headers": HDR_REQ}
op("put", "/admin/zones/{zoneId}/surge", "adminPutSurge", "Create or replace the zone's surge schedule (curve)", ["admin"], "Admin · Config",
   params=[pref("ZoneId")], body="SurgeScheduleCommand", ok=(200, "SurgeSchedule"), mutation=True, approval=True, permission="settings.publish", permission_v050="pricing.edit",
   desc="contract.json#surge, CONTRACT.md §3.4. Points above the zone's cap → 400 invalid_request. v0.7.2: runs at once for every admin with settings.publish (one admin is enough). New quotes price from it at once; quotes already given keep their multiplier.")
op("post", "/admin/zones/{zoneId}/surge/end", "adminEndSurge", "End the schedule now (back to ×1.0)", ["admin"], "Admin · Config",
   params=[pref("ZoneId")], body="ConfigPublishCommand", ok=(200, "SurgeSchedule"), mutation=True, permission="settings.publish", permission_v050="pricing.edit")
op("get", "/admin/audit", "adminListAudit", "Server-written audit log", ["admin"], "Admin · Governance",
   params=AL + [q("actorId", ref("Id")), q("targetType", {"type": "string"}), q("targetId", ref("Id")), q("action", {"type": "string"}),
                q("result", {"type": "string", "enum": ["committed", "rejected", "denied", "conflict", "pending_approval"]}), pref("From"), pref("To")],
   ok=(200, "AuditEntryPage"), permission="audit.read")
op("get", "/admin/approvals", "adminListApprovals", "Approval queue", ["admin"], "Admin · Governance",
   params=AL + [q("status", {"type": "string", "enum": ["pending_approval", "approved", "rejected", "expired"]}, multi=True),
                q("targetType", {"type": "string"})], ok=(200, "ApprovalPage"), permission="approval.decide", permission_v050="approval.read")
for d in ["approve", "reject"]:
    op("post", f"/admin/approvals/{{approvalId}}/{d}", f"adminApproval{d.capitalize()}", f"{d.capitalize()} a pending action (not the requester)",
       ["admin"], "Admin · Governance", params=[pref("ApprovalId")], body="ApprovalDecision", ok=(200, "Approval"), mutation=True,
       permission="approval.decide")

# ---- v0.5.1
# Admin sign-in (CONTRACT.md §9, owner decisions 9 and 14). No bearer token on sign-in, setup and refresh.
AU_A = C["auth"]["admin"]
for o in [
    op("post", "/admin/auth/sign-in", "adminSignIn", "Admin sign-in with e-mail and password", ["admin"], "Admin · Auth",
       body="AdminSignInRequest", ok=(200, "AdminSession"),
       desc="Unknown e-mail, wrong password or deactivated account → 401 unauthenticated with reason invalid_credentials (one generic answer). "
            "Failed attempts are slowed, then locked: 429 rate_limited with Retry-After. No second factor in v0.5.1; a SECOND_FACTOR_REQUIRED answer is reserved for later (contract.json#auth.admin.secondFactor)."),
    op("post", "/admin/auth/setup-password", "adminSetupPassword", "Choose the password from a one-time setup link", ["admin"], "Admin · Auth",
       body="SetupPasswordRequest", ok=(200, "AdminSession"),
       desc=f"Password shorter than {AU_A['passwordMinLength']} → 400 invalid_request (weak_password); unknown token → 400 invalid_request (invalid_setup_token); "
            f"a link older than {AU_A['setupLinkHours']} h → 410 otp_expired (setup_link_expired); used already → 410 otp_expired (setup_link_used). Signs the admin in."),
    op("post", "/admin/auth/setup-password/check", "adminCheckSetupLink", "Who a setup link is for, before the password form", ["admin"], "Admin · Auth",
       body="SetupTokenRequest", ok=(200, "SetupLinkInfo"), read_only=True, desc="Read-only: the link stays unused. Same 400 / 410 answers as setup-password."),
    op("post", "/admin/auth/refresh", "adminRefresh", "Rotate the admin refresh token", ["admin"], "Admin · Auth",
       body="RefreshRequest", ok=(200, "AdminSession"), desc=f"Rotated on every call; lives at most {AU_A['refreshExpiresHours']} h. A used, revoked or unknown token → 401 unauthenticated. Separate from /auth/refresh (rider and driver)."),
]:
    o["security"] = []
for p in ["/admin/auth/setup-password", "/admin/auth/setup-password/check"]:
    PATHS[p]["post"]["responses"]["410"] = err("otp_expired: the setup link expired (setup_link_expired) or was used (setup_link_used); ask for a new link.")
op("post", "/admin/auth/sign-out", "adminSignOut", "End this admin session", ["admin"], "Admin · Auth", ok=(204, None), desc="Revokes the refresh token; idempotent.")
op("get", "/admin/auth/me", "adminMe", "The signed-in admin: role, expanded permissions, scope", ["admin"], "Admin · Auth", ok=(200, "AdminMe"))
# v0.17.1 (owner 2026-10-29, "Fix fully (Recommended)"): the admin saves their own panel language (contract.json#auth.admin.meLanguage).
S["AdminMeUpdate"] = obj(OrderedDict([("language", nullable("Language")), ("firstName", {"oneOf": [s(minLength=1, maxLength=40), {"type": "null"}], "description": "v0.18.16: own first name; null clears it."})]), [], "v0.17.1: the signed-in admin's own panel language (null clears it); v0.18.16 also the own first name. At least one of them.")
S["AdminAgent"] = obj({"adminId": ref("Id"), "firstName": s(minLength=1, maxLength=40), "role": ref("AdminRole"), "zones": arr(s())}, ["adminId", "role", "zones"], "v0.18.16: an admin as Team shows him (never the e-mail).")
S["AdminAgentList"] = obj({"items": arr(ref("AdminAgent"))}, ["items"], "v0.18.16.")
S["AdminAgentNameCommand"] = obj({"firstName": {"oneOf": [s(minLength=1, maxLength=40), {"type": "null"}]}}, ["firstName"], "v0.18.16: another admin's first name; null clears it.")
op("patch", "/admin/auth/me", "adminUpdateMe", "Save the signed-in admin's own panel language or first name", ["admin"], "Admin · Auth",
   body="AdminMeUpdate", ok=(200, "AdminMe"), mutation=True,
   desc="v0.17.1: " + AA["meLanguage"]["note"].split(": ", 1)[1])
# v0.18.16 admin first names (contract.json#adminNames)
op("get", "/admin/agents", "adminListAgents", "Admins as Team shows them (first names, never e-mails)", ["admin"], "Admin · Auth", ok=(200, "AdminAgentList"), permission="team.read", desc="v0.18.16. " + C["adminNames"]["others"])
op("patch", "/admin/agents/{adminId}", "adminSetAgentName", "Set another admin's first name", ["admin"], "Admin · Auth", params=[{"name": "adminId", "in": "path", "required": True, "schema": ref("Id")}], body="AdminAgentNameCommand", ok=(200, "AdminAgent"), mutation=True, permission="team.edit", desc="v0.18.16. " + C["adminNames"]["others"])
op("post", "/admin/agents/{adminId}/setup-link", "adminIssueSetupLink", "Issue a one-time password setup link for an admin", ["admin"], "Admin · Auth",
   params=[pref("AdminId")], ok=(201, "SetupLink"), mutation=True, permission="team.edit",
   desc=f"Single use, {AU_A['setupLinkHours']} h; a new link revokes the admin's earlier unused one. The first Super admin's link comes from the server seed / CLI.")
# Locations and routes (CONTRACT.md §10, owner decision 4). Read-only POSTs: no Idempotency-Key.
op("post", "/locations/autocomplete", "autocompleteAddress", "Address suggestions while typing", ["rider", "driver"], "Maps",
   body="AutocompleteRequest", ok=(200, "AddressSuggestionList"), read_only=True,
   desc="Body uses latitude / longitude (wire exception). Google Places through the server; the server keeps its own session tokens and cache. An empty list = nothing found.")
op("post", "/locations/geocode", "geocodeAddress", "Coordinates for an address or a suggestion", ["rider", "driver"], "Maps",
   body="GeocodeRequest", ok=(200, "GeocodeResult"), read_only=True, desc="No match → 200 without coordinates (never 404).")
op("post", "/locations/reverse-geocode", "reverseGeocode", "Address of a point", ["rider", "driver"], "Maps",
   body="ReverseGeocodeRequest", ok=(200, "ReverseGeocodeResult"), read_only=True, desc="Bad coordinates → 400 invalid_request (invalid_coordinates).")
op("post", "/routes", "routeBetween", "Road route between two points (Movera OSRM)", ["rider", "driver"], "Maps",
   body="RouteRequest", ok=(200, "RoadRoute"), read_only=True, desc="No route → 404 not_found (reason no_route); the app then draws a straight line. lat / lng as everywhere else.")
op("get", "/routes/driving/{coordinates}", "osrmDrivingRoute", "Turn-by-turn route for driver navigation (OSRM v5 pass-through)", ["driver"], "Maps",
   params=[{"name": "coordinates", "in": "path", "required": True, "description": C["maps"]["osrm"]["coordinates"],
            "schema": {"type": "string", "pattern": r"^-?\d+(\.\d+)?,-?\d+(\.\d+)?(;-?\d+(\.\d+)?,-?\d+(\.\d+)?){1,9}$"}},
           q("overview", {"type": "string", "enum": ["full", "simplified", "false"], "default": "full"}),
           q("geometries", {"type": "string", "enum": C["maps"]["osrm"]["geometries"], "default": "geojson"}),
           q("steps", {"type": "boolean", "default": True}), q("annotations", {"type": "boolean", "default": False}),
           q("alternatives", {"type": "boolean", "default": False})],
   ok=(200, "OsrmRouteResponse"),
   desc=f"Same path syntax and query as OSRM /route/v1/driving. No route → 200 {{code: \"NoRoute\", routes: []}}. About {C['maps']['osrm']['rateLimitPerMinute']} per minute per driver (429). Auth and rate errors use Error.")
# Telemetry (CONTRACT.md §11): no auth required, no Idempotency-Key, standard headers optional.
for path, opid, summ, body in [("/telemetry/logs", "postTelemetryLog", "App log line", "TelemetryLog"),
                               ("/telemetry/analytics", "postTelemetryAnalytics", "App analytics event", "TelemetryEvent"),
                               ("/telemetry/crashes", "postTelemetryCrash", "App crash report", "TelemetryCrash")]:
    o = op("post", path, opid, summ, ["rider", "driver", "admin"], "Telemetry", body=body, ok=(202, None), read_only=True, ok_desc="Accepted (empty body)",
           desc=f"Fire-and-forget. Body at most {C['telemetry']['maxBodyBytes']} bytes (else 400 invalid_request, payload_too_large); rate limited per address and device; "
                f"scrubbed again by the server and kept {C['telemetry']['keepDays']} days. A bearer token is used when sent.")
    o["security"] = [{}, {"bearerAuth": []}]
# Rider: keep waiting, account deletion
op("post", "/trips/{tripId}/raise-price", "raisePrice", "Raise the offer while searching", ["rider"], "Rider · Booking",
   params=TID, body="RaisePriceCommand", ok=(200, TP), mutation=True, transition="raise_price",
   desc="Owner decision 25 (CONTRACT.md §3.6). While the trip is searching or offered: the fare grows by increase (a rider_raise fare line), the whole raise goes to the driver's "
        "earnings, open offers are withdrawn and a new search starts in which drivers who already declined are asked again at the new price; version + 1. "
        "Otherwise 409 invalid_transition with the projection. A raise in another currency or a fare above dispatch.raisePrice.maxFactor × the quoted fare is 400 invalid_request.")
op("post", "/trips/{tripId}/keep-waiting", "answerKeepWaiting", "Answer the Keep waiting? step while searching", ["rider"], "Rider · Booking",
   params=TID, body="KeepWaitingCommand", ok=(200, TP), mutation=True,
   desc="Owner decision 24 (CONTRACT.md §3.6). Only while the trip is searching or offered and its searchStep is an unanswered keep_waiting: wait → the search end moves by extraMin; "
        "stop → the normal free rider cancel (cancel → cancelled_by_rider, reason wait_too_long, no fee). Otherwise 409 invalid_transition with the projection.")
op("post", "/account/deletion", "requestAccountDeletion", "Ask to delete the rider account", ["rider"], "Rider · Account",
   ok=(202, "AccountDeletion"), mutation=True, ok_desc="Accepted; the server erases the account on its own schedule.")
op("get", "/trips/{tripId}/path", "getTripPath", "The route of an ended trip (driven or planned)", ["rider", "driver"], "Trips",
   params=TID, ok=(200, "TripPath"),
   desc="v0.17.0 (CONTRACT.md §25): " + TPATH["actors"] + ". " + TPATH["driven"] + " " + TPATH["planned"])["responses"]["409"] = rref("Conflict")
op("get", "/driver/trips/{tripId}/complete-preview", "previewCompleteTrip", "The final price before completing (read-only)", ["driver"], "Driver · Trip",
   params=TID, ok=(200, "CompletePreview"),
   desc="v0.18.1 (CONTRACT.md §26): " + CPV["actors"] + " " + CPV["same"] + " " + CPV["frozen"] + " " + CPV["cashCollected"])["responses"]["409"] = rref("Conflict")
# Admin: dispatch control, live drivers, trip trace
op("get", "/admin/zones/{zoneId}/dispatch-control", "adminGetDispatchControl", "The zone's live dispatch switch", ["admin"], "Admin · Dispatch",
   params=[pref("ZoneId")], ok=(200, "DispatchControl"), permission="trips.read")
op("put", "/admin/zones/{zoneId}/dispatch-control", "adminPutDispatchControl", "Pause dispatch or force a mode in a zone", ["admin"], "Admin · Dispatch",
   params=[pref("ZoneId")], body="DispatchControlCommand", ok=(200, "DispatchControl"), mutation=True, approval=True, permission="dispatch.edit",
   desc="CONTRACT.md §3.6. v0.7.2 (one admin is enough): pause, force a mode, resume and back to rules run at once (200) for every admin with dispatch.edit. "
        "Forcing a mode that is off → 400 invalid_request (mode_off). Running searches stop new offers while paused; a forced mode applies to new searches.")
op("get", "/admin/live/drivers", "adminLiveDrivers", "Driver positions for the admin live map", ["admin"], "Admin · Dispatch",
   params=ZF + [q("limit", i(minimum=1, maximum=1000), "v0.18.34 §65: page size; without it every driver in one answer."), q("cursor", s(minLength=1, maxLength=128), "v0.18.34 §65: the nextCursor of the page before.")],
   ok=(200, "LiveDriverList"), permission="trips.read",
   desc="Limited to the zones in the admin's scope. stale = no fix for staleAfterSeconds. v0.18.34 §65: " + C["liveDriversPaging"]["adminLiveCard"] + ZF_DESC)
DDF = C["dispatchDriverFacts"]
def _nn(desc, **kw): return {"oneOf": [n(**kw), {"type": "null"}], "description": desc}
def _ni(desc, **kw): return {"oneOf": [i(**kw), {"type": "null"}], "description": desc}
S["DispatchDriverFacts"] = obj(OrderedDict([("driverId", ref("Id")), ("zoneId", ref("Id")), ("state", s(enum=["free", "trip"])),
    ("rating", _nn(DDF["real"]["rating"], minimum=0, maximum=5)), ("acceptancePct", _nn(DDF["real"]["acceptancePct"], minimum=0, maximum=100)),
    ("cancelPct", _nn(DDF["real"]["cancelPct"], minimum=0, maximum=100)), ("idleMin", _ni(DDF["real"]["idleMin"], minimum=0)),
    ("categoryIds", arr(s(), description=DDF["real"]["categoryIds"])), ("missedInRow", i(DDF["real"]["missedInRow"], minimum=0)),
    ("ridesThisHour", i(DDF["real"]["ridesThisHour"], minimum=0)), ("restNeeded", b(DDF["real"]["restNeeded"]))]
    + [(k, {"type": "null", "description": DDF["notYetRule"]}) for k in DDF["notYet"]]),
    required=["driverId", "zoneId", "state", "rating", "acceptancePct", "cancelPct", "idleMin", "categoryIds", "missedInRow", "ridesThisHour", "restNeeded"] + DDF["notYet"],
    desc="v0.18.21 (contract.json#dispatchDriverFacts): what dispatch knows about one online driver.")
S["DispatchDriverFactsList"] = obj({"zoneId": ref("Id"), "serverTime": ref("Timestamp"), "items": arr(ref("DispatchDriverFacts"))}, required=["zoneId", "serverTime", "items"])
op("get", "/admin/zones/{zoneId}/driver-facts", "adminDispatchDriverFacts", "Real dispatch facts of the zone's online drivers", ["admin"], "Admin · Dispatch",
   params=[pref("ZoneId")], ok=(200, "DispatchDriverFactsList"), permission="trips.read",
   desc="v0.18.21 (contract.json#dispatchDriverFacts): " + DDF["who"] + " " + DDF["notYetRule"] + " A zone outside the admin's scope: 403 forbidden (zone_out_of_scope); unknown zone: 404.")
op("get", "/admin/trips/{tripId}/trace", "adminTripTrace", "The trip's GPS trace", ["admin"], "Admin · Trips",
   params=TID, ok=(200, "TripTrace"), permission="trips.read", desc="Traces are deleted 30 days after the trip (owner decision 11): 404 after that.")
