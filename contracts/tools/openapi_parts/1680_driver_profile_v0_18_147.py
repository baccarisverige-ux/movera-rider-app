# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.147 (driver profile v3; owner
# 2026-11-20 "Now build all"; contract.json#driverProfile): the rider's driver profile sheet, compliments, moderated short
# reviews, languages, milestones, the driver's Min profil and the admin moderation list; per-zone switches. Additive.
_DP = C["driverProfile"]
_V147 = "v0.18.147 (contract.json#driverProfile): "
for _n in ("DriverPublicProfile", "DriverOwnPublicProfile", "DriverPublicProfilePatch", "AdminDriverReview", "AdminDriverReviewPage", "DriverProfileSettings"):
    assert _n not in S, _n + " exists before v0.18.147"
assert "/rider/trips/{tripId}/driver-profile" not in PATHS and "/driver/public-profile" not in PATHS, "routes exist before v0.18.147"
_CODES = [x["code"] for x in _DP["compliments"]["list"]]
assert set(_CODES) == set(C["ratings"]["tags"]["aboutDriver"]), "chips are aboutDriver codes"
_RV = _DP["review"]
_MONTH = s("YYYY-MM in the trip zone's time zone.", pattern=r"^[0-9]{4}-[0-1][0-9]$")
_LANG = arr(s(enum=_DP["languages"]["codes"]), maxItems=_DP["languages"]["max"], uniqueItems=True)
S["DriverCompliment"] = obj(OrderedDict([("code", s(enum=_CODES)), ("count", i(minimum=1))]), ["code", "count"], _V147 + _DP["compliments"]["counts"], addl=False)
S["DriverMilestone"] = obj(OrderedDict([("code", s(enum=["trips_1000", "top_rating"])), ("reachedAt", _MONTH)]), ["code", "reachedAt"], _V147 + _DP["milestones"]["rule"], addl=False)
S["DriverReviewShown"] = obj(OrderedDict([("text", s(minLength=1, maxLength=_RV["maxLength"])), ("name", {"oneOf": [s(maxLength=20), {"type": "null"}]}), ("month", _MONTH)]),
                             ["text", "name", "month"], _V147 + _RV["reviewName"], addl=False)
S["DriverPublicProfile"] = obj(OrderedDict([
    ("driverId", ref("Id")), ("firstName", s(minLength=1)), ("verified", b(_DP["verified"])),
    ("photoUrl", {"oneOf": [s(format="uri-reference"), {"type": "null"}], "description": "The same driver-photo path as DriverSummary.photoUrl, or null."}),
    ("languages", _LANG), ("city", {"oneOf": [s(maxLength=80), {"type": "null"}], "description": "null when the driver hides it (showCity false)."}),
    ("sinceMonth", {"oneOf": [_MONTH, {"type": "null"}], "description": "null when the driver hides it (showYears false)."}),
    ("years", {"oneOf": [i(minimum=0), {"type": "null"}], "description": "null when the driver hides it."}),
    ("tripCount", i(minimum=0)), ("rating", {"oneOf": [n(minimum=0, maximum=5), {"type": "null"}]}),
    ("compliments", arr(ref("DriverCompliment"), maxItems=len(_CODES))), ("milestones", arr(ref("DriverMilestone"), maxItems=2)),
    ("latestReview", nullable("DriverReviewShown")),
]), ["driverId", "firstName", "verified", "photoUrl", "languages", "city", "sinceMonth", "years", "tripCount", "rating", "compliments", "milestones", "latestReview"],
    _V147 + _DP["kpis"] + " " + _DP["load"], addl=False)
op("get", "/rider/trips/{tripId}/driver-profile", "riderTripDriverProfile", "The trip driver's profile", ["rider"], "Rider · Trips", params=TID,
   ok=(200, "DriverPublicProfile"), desc=_V147 + _DP["routes"]["rider"] + " " + _DP["load"])
_r = PATHS["/rider/trips/{tripId}/driver-profile"]["get"]["responses"]
_r["200"]["headers"] = dict(_r["200"]["headers"], **{"Cache-Control": {"schema": {"type": "string"}}, "ETag": {"schema": {"type": "string"}}})
_r["304"] = {"description": "Not modified (If-None-Match matched the ETag)."}
_RS = OrderedDict([("reviewId", ref("Id")), ("text", s(maxLength=_RV["maxLength"])), ("name", {"oneOf": [s(maxLength=20), {"type": "null"}]}), ("month", _MONTH),
                   ("stars", i(minimum=_RV["minStarsShown"], maximum=5)), ("status", s(enum=["pending", "approved", "hidden"]))])
S["DriverOwnReview"] = obj(_RS, list(_RS.keys()), _V147 + _RV["moderation"], addl=False)
S["DriverOwnPublicProfile"] = obj(OrderedDict([
    ("languages", _LANG), ("showCity", b()), ("showYears", b()), ("profileOn", b("The zone's driver profile switch.")), ("reviewsOn", b("The zone's written reviews switch.")),
    ("preview", ref("DriverPublicProfile")), ("compliments", arr(ref("DriverCompliment"))), ("reviews", arr(ref("DriverOwnReview"), maxItems=50)),
]), ["languages", "showCity", "showYears", "profileOn", "reviewsOn", "preview", "compliments", "reviews"], _V147 + _DP["routes"]["driverRead"], addl=False)
S["DriverPublicProfilePatch"] = obj(OrderedDict([("languages", _LANG), ("showCity", b()), ("showYears", b())]), (), _V147 + _DP["routes"]["driverWrite"], addl=False, minProperties=1)
op("get", "/driver/public-profile", "getDriverPublicProfile", "Min profil: what riders see", ["driver"], "Driver · Account", ok=(200, "DriverOwnPublicProfile"),
   desc=_V147 + _DP["routes"]["driverRead"])
op("patch", "/driver/public-profile", "updateDriverPublicProfile", "Min profil: languages and what to show", ["driver"], "Driver · Account", body="DriverPublicProfilePatch",
   ok=(200, "DriverOwnPublicProfile"), mutation=True, desc=_V147 + _DP["routes"]["driverWrite"])
_AR = OrderedDict([("reviewId", ref("Id")), ("driverId", ref("Id")), ("driverFirstName", s()), ("zoneId", ref("Id"))] + [(k, v) for k, v in _RS.items() if k != "reviewId"] + [("createdAt", ref("Timestamp"))])
S["AdminDriverReview"] = obj(_AR, list(_AR.keys()), _V147 + _DP["routes"]["adminList"], addl=False)
S["AdminDriverReviewPage"] = obj({"items": arr(ref("AdminDriverReview")), "nextCursor": {"type": ["string", "null"]}}, ["items", "nextCursor"], _V147 + _DP["routes"]["adminList"])
op("get", "/admin/driver-reviews", "adminListDriverReviews", "Driver reviews to moderate", ["admin"], "Admin · Reviews",
   params=AL + [q("status", s(enum=["pending", "approved", "hidden"])), pref("ListZoneId")], ok=(200, "AdminDriverReviewPage"), permission="settings.read",
   desc=_V147 + _DP["routes"]["adminList"])
_RID = [{"name": "reviewId", "in": "path", "required": True, "schema": ref("Id")}]
for _verb, _summ in (("approve", "Show a driver review"), ("hide", "Hide a driver review")):
    op("post", "/admin/driver-reviews/{reviewId}/" + _verb, "admin" + _verb.capitalize() + "DriverReview", _summ, ["admin"], "Admin · Reviews", params=_RID,
       ok=(200, "AdminDriverReview"), mutation=True, permission="settings.publish", desc=_V147 + _DP["routes"]["adminModerate"])
# --- the rating
_RQ = S["RatingRequest"]["properties"]
assert "review" not in _RQ and "reviewName" not in _RQ, "RatingRequest.review exists before v0.18.147"
_RQ["review"] = s(_V147 + _RV["field"], minLength=1, maxLength=_RV["maxLength"])
_RQ["reviewName"] = {**s(_V147 + _RV["reviewName"], enum=["first_name", "anonymous"]), "default": "first_name"}
_RQ["tags"]["maxItems"] = C["ratings"]["tags"]["maxPerRating"]
# --- the zone's switches
S["DriverProfileSettings"] = obj(OrderedDict([("on", {**b("The zone's driver profile switch."), "default": C["configDefaults"]["driverProfileOn"]}),
                                             ("reviews", {**b("The zone's written reviews switch."), "default": C["configDefaults"]["driverReviewsOn"]})]), (), _V147 + _DP["setting"])
S["RiderAppConfig"]["properties"]["driverProfile"] = ref("DriverProfileSettings")
S["DriverAppConfig"]["properties"]["driverProfile"] = ref("DriverProfileSettings")
