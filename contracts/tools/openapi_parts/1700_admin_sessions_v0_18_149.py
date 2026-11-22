# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.149 (owner Rules
# decisions/driver-g12.md Q6 "Real, riders + drivers (Recommended)"; contract.json#adminSessions): an admin lists a
# rider's / driver's signed-in sessions and signs one or all out with a reason; the phone hears signed_out_by_movera.
_AS = C["adminSessions"]
_V149 = "v0.18.149 (contract.json#adminSessions): "
for _p in ("/admin/riders/{riderId}/sessions", "/admin/drivers/{driverId}/sessions"):
    assert _p not in PATHS, _p + " exists before v0.18.149"
S["AdminSession"] = obj(OrderedDict([
    ("sessionId", ref("Id")),
    ("app", s(enum=["rider", "driver"])),
    ("device", {"oneOf": [s(maxLength=40), {"type": "null"}], "description": _AS["list"]["device"]}),
    ("platform", s(enum=["ios", "android", "web", "unknown"])),
    ("appVersion", {"oneOf": [s(maxLength=40), {"type": "null"}]}),
    ("lastSeenAt", ref("Timestamp")),
    ("createdAt", ref("Timestamp")),
]), ["sessionId", "app", "device", "platform", "appVersion", "lastSeenAt", "createdAt"], _V149 + "one signed-in phone. " + _AS["list"]["privacy"], addl=False)
S["AdminSessionList"] = obj({"items": arr(ref("AdminSession"), maxItems=50)}, ["items"], _V149 + _AS["list"]["order"])
S["AdminSessionSignOutCommand"] = obj(OrderedDict([
    ("sessionId", ref("Id")),
    ("all", {"type": "boolean", "const": True}),
    ("reason", s(minLength=1, maxLength=500)),
]), ["reason"], _V149 + _AS["signOut"]["body"] + " " + _AS["signOut"]["reason"], addl=False)
S["AdminSessionSignOutResult"] = obj(OrderedDict([
    ("signedOut", i(minimum=0)),
    ("items", arr(ref("AdminSession"), maxItems=50)),
]), ["signedOut", "items"], _V149 + _AS["signOut"]["answer"])
_SO_DESC = " ".join(_AS["signOut"][k] for k in ("effect", "driverOnTrip", "notFound", "idempotency", "audit"))
for _who, _P, _par in (("rider", "riders", "RiderId"), ("driver", "drivers", "DriverId")):
    _W = _who[0].upper() + _who[1:]
    op("get", "/admin/" + _P + "/{" + _who + "Id}/sessions", "adminList" + _W + "Sessions", "A " + _who + "'s signed-in sessions", ["admin"], "Admin · People",
       params=[pref(_par)], ok=(200, "AdminSessionList"), permission=_AS["permissions"]["list" + _W],
       desc=_V149 + _AS["note"] + " " + _AS["scope"] + " " + _AS["list"]["device"] + " " + _AS["list"]["privacy"])
    op("post", "/admin/" + _P + "/{" + _who + "Id}/sessions/sign-out", "adminSignOut" + _W + "Sessions", "Sign a " + _who + " out of one or all sessions (reason, audited)", ["admin"], "Admin · People",
       params=[pref(_par)], body="AdminSessionSignOutCommand", ok=(200, "AdminSessionSignOutResult"), mutation=True, permission=_AS["permissions"]["signOut" + _W],
       desc=_V149 + _AS["scope"] + " " + _SO_DESC)
_rf = PATHS["/auth/refresh"]["post"]
_rf["description"] = (_rf.get("description", "") + " " + _V149 + "reason signed_out_by_movera: an admin signed this phone out (" + _AS["apps"]["show"] + ")").strip()
