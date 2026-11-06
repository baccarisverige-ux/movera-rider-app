# v0.18.43 §64 (fix job 10, contract.json#blockedPairs): never match a rider and a driver again; rider level screens.
# A part of tools/gen_openapi.py (rule 25 split), run in name order with its globals (after 0390, before 0400_paths).
BP = C["blockedPairs"]
BPD = C["configDefaults"]["dontMatchAgain"]
BPR = BP["settings"]["ranges"]
S["BlockedPair"] = obj({
    "pairId": ref("Id"), "riderId": ref("Id"), "driverId": ref("Id"),
    "by": s(enum=BP["by"]), "reason": s(maxLength=300), "tripId": ref("Id"),
    "at": ref("Timestamp"), "adminId": ref("Id"),
}, ["pairId", "riderId", "driverId", "by", "at"], "v0.18.43 §64: " + BP["pair"] + " " + BP["dispatch"] + " " + BP["neverTold"])
S["BlockedPairList"] = obj({"items": arr(ref("BlockedPair"))}, ["items"], "v0.18.43 §64: " + BP["admin"])
S["BlockPairCommand"] = obj({"reason": s(minLength=1, maxLength=300)}, [], "v0.18.43 §64: " + BP["admin"], addl=False)
_DM = obj({"on": {**b(), "default": BPD["on"]},
           "atStars": {**i("The tick shows at this many stars or fewer.", minimum=BPR["atStars"][0], maximum=BPR["atStars"][1]), "default": BPD["atStars"]}},
          [], "v0.18.43 §64: " + BP["settings"]["where"])
S["DontMatchAgainSettings"] = _DM
S["CountryRules"]["properties"]["dontMatchAgain"] = ref("DontMatchAgainSettings")
S["RiderAppConfig"]["properties"]["dontMatchAgain"] = {"allOf": [ref("DontMatchAgainSettings")], "description": "v0.18.43 §64: written by the server from the zone's CountryRules. " + BP["apps"]["tick"]}
S["DriverAppConfig"]["properties"]["dontMatchAgain"] = {"allOf": [ref("DontMatchAgainSettings")], "description": "v0.18.43 §64: written by the server from the zone's CountryRules. " + BP["apps"]["tick"]}
S["RatingRequest"]["properties"]["dontMatchAgain"] = b("v0.18.43 §64: " + BP["rating"] + " " + BP["neverTold"])
PATHS["/trips/{tripId}/rating"]["post"]["description"] = PATHS["/trips/{tripId}/rating"]["post"].get("description", "") + " v0.18.43 §64: " + BP["rating"]
op("post", "/admin/trips/{tripId}/block-pair", "adminBlockPair", "Never match this trip's rider and driver again", ["admin"], "Admin · Trips",
   params=TID, body="BlockPairCommand", ok=(200, "BlockedPair"), mutation=True, permission="riders.block", desc="v0.18.43 §64: " + BP["admin"] + " " + BP["neverTold"])
op("delete", "/admin/blocked-pairs/{pairId}", "adminRemoveBlockedPair", "Undo a blocked pair (Support only)", ["admin"], "Admin · Trips",
   params=[{"name": "pairId", "in": "path", "required": True, "schema": ref("Id")}], ok=(204, None), mutation=True, permission="riders.block", desc="v0.18.43 §64: " + BP["undo"])
op("get", "/admin/blocked-pairs", "adminBlockedPairs", "The active blocked pairs of one rider or one driver", ["admin"], "Admin · Trips",
   params=[{"name": "riderId", "in": "query", "required": False, "schema": ref("Id")}, {"name": "driverId", "in": "query", "required": False, "schema": ref("Id")}],
   ok=(200, "BlockedPairList"), permission="riders.read", desc="v0.18.43 §64: " + BP["admin"])
