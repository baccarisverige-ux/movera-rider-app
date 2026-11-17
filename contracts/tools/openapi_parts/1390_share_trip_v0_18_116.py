# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.116 (BQ-S10; owner 2026-11-02 Q1
# "Build it for real (Recommended)", Rules decisions/driver-g14.md:11, and the S10 button answers of 2026-11-15, same file):
# the rider's live trip link (contract.json#shareTrip). 3 rider routes, 2 public routes (no sign-in), the fixed public
# allow-list, EmergencyContact.shareTrips and RiderAppConfig.shareTrip { on }. Additive.
_ST = C["shareTrip"]
_V116 = "v0.18.116 (contract.json#shareTrip): "
for _n in ("TripShareLink", "TripShareItem", "TripShareList", "PublicTripShare", "PublicTripShareEnded"):
    assert _n not in S, _n + " exists before v0.18.116"
assert "shareTrips" not in S["EmergencyContact"]["properties"], "EmergencyContact.shareTrips exists before v0.18.116"
assert "shareTrip" not in S["RiderAppConfig"]["properties"], "RiderAppConfig.shareTrip exists before v0.18.116"
assert "shareTrip" not in S["DriverAppConfig"]["properties"], "the driver document has no shareTrip"

# --- the rider's side
_ITEM = OrderedDict([("shareId", ref("Id")), ("tripId", ref("Id")), ("createdAt", ref("Timestamp")),
                     ("expiresAt", {"allOf": [ref("Timestamp")], "description": f"createdAt + {_ST['maxHours']} h (shareTrip.maxHours); the link ends earlier at drop-off."}),
                     ("endsAtDropoff", {"type": "boolean", "enum": [True]})])
S["TripShareItem"] = obj(_ITEM, ["shareId", "tripId", "createdAt", "expiresAt", "endsAtDropoff"], _V116 + _ST["routes"]["list"], addl=False)
S["TripShareLink"] = obj(OrderedDict(list(_ITEM.items()) + [("url", s(_ST["link"]["url"] + " " + _ST["link"]["token"], format="uri"))]),
                         ["shareId", "tripId", "url", "createdAt", "expiresAt", "endsAtDropoff"], _V116 + _ST["routes"]["create"], addl=False)
S["TripShareList"] = obj({"items": arr(ref("TripShareItem"), maxItems=_ST["limits"]["maxActivePerTrip"])}, ["items"], _V116 + _ST["routes"]["list"], addl=False)
_SP = "/rider/trips/{tripId}/share"
op("post", _SP, "riderShareTrip", "Make a live trip link", ["rider"], "Rider · Safety", params=TID, ok=(201, "TripShareLink"), mutation=True,
   desc=_V116 + _ST["routes"]["create"] + " " + _ST["notLive"] + " " + _ST["ends"])
op("get", _SP, "riderTripShares", "The trip's live links", ["rider"], "Rider · Safety", params=TID, ok=(200, "TripShareList"),
   desc=_V116 + _ST["routes"]["list"])
op("delete", _SP, "riderStopShareTrip", "Stop sharing the trip", ["rider"], "Rider · Safety", params=TID, ok=(204, None), mutation=True,
   desc=_V116 + _ST["routes"]["revoke"])

# --- the public side: a FIXED allow-list (additionalProperties false on every level)
_PUB = _ST["public"]
_CAR = obj(OrderedDict((k, s(maxLength=80)) for k in _PUB["car"]), _PUB["car"], "The car as on the trip. No driver name, photo or rating.", addl=False)
_ETA = obj(OrderedDict([("minutes", i(minimum=1)), ("target", s(enum=["pickup", "dropoff"])),
                        ("arriveAround", s("HH:MM in the trip zone's time zone.", pattern=r"^[0-2][0-9]:[0-5][0-9]$"))]),
           _PUB["eta"], _PUB["etaRule"], addl=False)
_POS = obj(OrderedDict([("lat", n(minimum=-90, maximum=90)), ("lng", n(minimum=-180, maximum=180)), ("at", ref("Timestamp"))]),
           _PUB["position"], _PUB["positionRule"], addl=False)
S["PublicTripShare"] = obj(OrderedDict([
    ("state", s(enum=["live"])),
    ("phase", s(enum=list(_PUB["phases"].keys()) + [_PUB["queuedPhase"]], **{"x-statuses": _PUB["phases"]})),
    ("car", _CAR),
    ("eta", {"oneOf": [_ETA, {"type": "null"}]}),
    ("position", {"oneOf": [_POS, {"type": "null"}]}),
    ("updatedAt", ref("Timestamp")),
    ("refreshSeconds", i(enum=[_PUB["refreshSeconds"]])),
]), _PUB["fields"], _V116 + _PUB["shape"] + " Never: " + "; ".join(_PUB["never"]) + ".", addl=False, **{"x-never": _PUB["never"]})
assert list(S["PublicTripShare"]["properties"].keys()) == _PUB["fields"], "PublicTripShare = shareTrip.public.fields"
S["PublicTripShareEnded"] = obj(OrderedDict([("state", s(enum=["ended"])), ("reason", s(enum=["share_ended"]))]), ["state", "reason"],
                                _V116 + _ST["ends"], addl=False)
S["PublicTripShareSearching"] = obj(OrderedDict([("state", s(enum=["searching"])), ("updatedAt", ref("Timestamp")), ("refreshSeconds", i(enum=[_PUB["refreshSeconds"]]))]),
                                    ["state", "updatedAt", "refreshSeconds"], _V116 + _PUB["searching"], addl=False)
_TOKEN = [{"name": "token", "in": "path", "required": True, "description": _ST["link"]["token"],
           "schema": s(pattern=_ST["link"]["tokenPattern"])}]
_HDRS = {k: {"schema": {"type": "string"}} for k in ("Cache-Control", "Referrer-Policy", "X-Robots-Tag", "X-Content-Type-Options")}
def _public(o, ended, missing):
    o["security"] = []
    o["x-public"] = True
    o["parameters"] = [p for p in o["parameters"] if p.get("$ref", "").split("/")[-1] not in ("RequestId", "ApiVersion")]
    r = o["responses"]
    for code in ("400", "401", "403"): r.pop(code)
    r["200"]["headers"] = dict(r["200"]["headers"], **_HDRS)
    r["404"] = missing
    r["410"] = ended
    o["responses"] = OrderedDict((k, r[k]) for k in ("200", "404", "410", "429", "503"))
    return o
_public(op("get", "/share/{token}", "publicTripShare", "A shared trip (no sign-in)", [], "Public · Share trip", params=_TOKEN, ok=(200, "PublicTripShare"),
           desc=_V116 + _ST["routes"]["publicJson"] + " " + _PUB["headers"] + " " + _ST["limits"]["note"]),
        err("The link has ended (share_ended): no trip data.", "PublicTripShareEnded"), err("not_found, reason share_not_found: the same answer for every miss."))
PATHS["/share/{token}"]["get"]["responses"]["200"]["content"]["application/json"]["schema"] = {"oneOf": [ref("PublicTripShare"), ref("PublicTripShareSearching")]}
_html = {"text/html": {"schema": {"type": "string", "description": "The share page. No script, no preview tags with trip data."}}}
_o = _public(op("get", "/s/{token}", "publicTripSharePage", "The shared trip page (HTML, no sign-in)", [], "Public · Share trip", params=_TOKEN,
                content=_html, desc=_V116 + _ST["routes"]["publicPage"] + " " + _PUB["headers"] + " " + _PUB["preview"] + " " + _ST["language"]),
             {"description": "The link has ended: the page says so and shows no trip data.", "content": _html},
             {"description": "Link not found: the same page for every miss.", "content": _html})
_o["responses"]["429"] = {"description": "rate_limited: a short HTML page; obey Retry-After.",
                          "headers": {"Retry-After": {"schema": {"type": "integer", "minimum": 0}}}, "content": _html}
_o["servers"] = [{"url": "https://api.dev.movera.invalid", "description": "The server's origin, outside /api/v1."}]

# --- trusted contacts and the zone's switch
S["EmergencyContact"]["properties"]["shareTrips"] = b(_V116 + _ST["contacts"])
S["RiderAppConfig"]["properties"]["shareTrip"] = obj({"on": {**b("The zone's switch."), "default": C["configDefaults"]["shareTripOn"]}},
                                                     desc=_V116 + _ST["setting"])
S["RiderAppConfig"]["properties"]["features"]["properties"]["shareTrip"] = b(_V116 + "the same value as shareTrip.on (served by the server).")
