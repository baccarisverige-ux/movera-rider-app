# v0.18.54 §76 (admin masking of phone, e-mail and date of birth; Reveal with a reason; SOS reveal, contract.json#adminMasking).
# A part of tools/gen_openapi.py (rule 25 split), run in name order with its globals, after 0200 / 0500 define the people lists and the trip reveal.
AM = C["adminMasking"]
_MASK_R = " Masked for admins without riders.viewSensitive (v0.18.54 §76): " + AM["shapes"]["phone"].split(",")[0] + "; the admin accepts both shapes."
_MASK_D = " Masked for admins without drivers.viewSensitive (v0.18.54 §76):"
S["Rider"]["properties"]["phone"]["description"] = "The rider's phone (E.164)." + _MASK_R
S["Rider"]["properties"]["email"]["description"] = "The rider's e-mail." + " Masked for admins without riders.viewSensitive (v0.18.54 §76): " + AM["shapes"]["email"]
S["Rider"]["properties"]["sensitiveMasked"] = b("v0.18.54 §76: true on an admin answer when phone / email were masked (the admin lacks riders.viewSensitive); absent when the values are full. The admin shows Reveal (POST /admin/riders/{riderId}/reveal).")
S["Driver"]["properties"]["email"]["description"] += _MASK_D + " " + AM["shapes"]["email"]
S["Driver"]["properties"]["dateOfBirth"]["description"] += _MASK_D + " " + AM["shapes"]["dateOfBirth"]
S["Driver"]["properties"]["sensitiveMasked"] = b("v0.18.54 §76: true on an admin answer when phone / email / dateOfBirth were masked (the admin lacks drivers.viewSensitive); absent when the values are full. The admin shows Reveal (POST /admin/drivers/{driverId}/reveal).")
S["Fleet"]["properties"]["ownerEmail"]["description"] += _MASK_D + " " + AM["shapes"]["email"]
S["Fleet"]["properties"]["sensitiveMasked"] = b("v0.18.54 §76: true on an admin answer when ownerEmail was masked (the admin lacks drivers.viewSensitive); absent when the value is full. The admin shows Reveal (POST /admin/fleets/{fleetId}/reveal).")
S["WaitlistEntry"]["properties"]["phone"] = {"type": "string", "description": "E.164 for an admin with riders.viewSensitive; v0.18.54 §76: " + AM["masked"]["waitlist"] + " The admin accepts both shapes."}
for _p, _k in (("/admin/riders", "riders"), ("/admin/drivers", "drivers"), ("/admin/fleets", "fleets"), ("/admin/waitlist", "waitlist")):
    PATHS[_p]["get"]["description"] = (PATHS[_p]["get"].get("description", "") + " v0.18.54 §76: " + AM["masked"][_k] + (" " + AM["search"] if _k == "riders" else "")).strip()
PATHS["/admin/drivers/{driverId}"]["get"]["description"] += " v0.18.54 §76: " + AM["masked"]["drivers"]
PATHS["/admin/fleets/{fleetId}"]["get"]["description"] += " v0.18.54 §76: " + AM["masked"]["fleets"]
PATHS["/admin/refunds/payouts"]["get"]["description"] += " v0.18.54 §76: " + AM["notMasked"]["refundPayouts"]

S["AdminRevealCommand"] = obj({"reason": s("Why the admin needs the values; audited, never the values.", minLength=3, maxLength=200)}, ["reason"],
                              "v0.18.54 §76: " + AM["reveal"]["reason"])
S["RevealedRider"] = obj({"riderId": ref("Id"), "phone": s(pattern=r"^\+[1-9]\d{6,14}$"), "email": s(format="email"), "revealedAt": ref("Timestamp")},
                         ["riderId", "phone", "revealedAt"], "v0.18.54 §76: the full values, once; the admin never stores them.")
S["RevealedDriver"] = obj({"driverId": ref("Id"), "phone": s("When the driver record has one.", pattern=r"^\+[1-9]\d{6,14}$"), "email": s(format="email"),
                           "dateOfBirth": s("YYYY-MM-DD.", format="date"), "revealedAt": ref("Timestamp")},
                          ["driverId", "revealedAt"], "v0.18.54 §76: the full values, once; the admin never stores them.")
S["RevealedFleet"] = obj({"fleetId": ref("Id"), "ownerEmail": s(format="email"), "revealedAt": ref("Timestamp")},
                         ["fleetId", "ownerEmail", "revealedAt"], "v0.18.54 §76: the full value, once.")
_REVEAL_DESC = " " + AM["reveal"]["scope"] + " " + AM["reveal"]["reason"] + " " + AM["reveal"]["idempotency"] + " " + AM["reveal"]["withRight"]
op("post", "/admin/riders/{riderId}/reveal", "adminRevealRider", "Show a rider's full phone and e-mail (reason, audited)", ["admin"], "Admin · People",
   params=[pref("RiderId")], body="AdminRevealCommand", ok=(200, "RevealedRider"), mutation=True, permission="riders.read",
   desc="v0.18.54 §76: " + AM["reveal"]["rider"] + _REVEAL_DESC + " Audited rider.reveal { reason }.")
op("post", "/admin/drivers/{driverId}/reveal", "adminRevealDriver", "Show a driver's full phone, e-mail and date of birth (reason, audited)", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="AdminRevealCommand", ok=(200, "RevealedDriver"), mutation=True, permission="drivers.read",
   desc="v0.18.54 §76: " + AM["reveal"]["driver"] + _REVEAL_DESC + " Audited driver.reveal { reason }.")
op("post", "/admin/fleets/{fleetId}/reveal", "adminRevealFleet", "Show a fleet's full owner e-mail (reason, audited)", ["admin"], "Admin · People",
   params=[pref("FleetId")], body="AdminRevealCommand", ok=(200, "RevealedFleet"), mutation=True, permission="drivers.read",
   desc="v0.18.54 §76: " + AM["reveal"]["fleet"] + _REVEAL_DESC + " Audited fleet.reveal { reason }.")

S["AdminIncidentRevealCommand"] = obj({"reason": s("Defaults to \"SOS\" when omitted.", minLength=1, maxLength=200)}, (), "v0.18.54 §76: " + AM["sosReveal"]["reason"])
_PH = {"oneOf": [obj({"phone": {"type": ["string", "null"], "description": "E.164; null when the record has no phone."}}, ["phone"]), {"type": "null"}],
       "description": "null when the incident has no account on that side."}
S["RevealedIncidentContacts"] = obj({"incidentId": ref("Id"), "rider": _PH, "driver": _PH, "revealedAt": ref("Timestamp")},
                                    ["incidentId", "rider", "driver", "revealedAt"], "v0.18.54 §76: " + AM["sosReveal"]["why"])
op("post", "/admin/incidents/{incidentId}/reveal-contacts", "adminIncidentRevealContacts", "Show the rider's and the driver's phone numbers of an open safety case (one click, audited)", ["admin"], "Admin · Safety",
   params=[pref("IncidentId")], body="AdminIncidentRevealCommand", ok=(200, "RevealedIncidentContacts"), mutation=True, permission="incidents.read",
   desc="v0.18.54 §76: " + AM["sosReveal"]["route"] + " " + AM["sosReveal"]["who"] + " " + AM["sosReveal"]["reason"] + " " + AM["sosReveal"]["audit"] + " " + AM["sosReveal"]["driverPhone"] + " " + AM["reveal"]["idempotency"])
