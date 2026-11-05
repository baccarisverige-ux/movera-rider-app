# v0.18.39 §63 (fix job N2 + P17 + far rider, contract.json#noDriverNearby).
# A part of tools/gen_openapi.py (rule 25 split), run in name order with its globals (after 0300, before 0400).
ND = C["noDriverNearby"]
NDD = ND["defaults"]
NDR = ND["ranges"]
S["DispatchDocument"]["properties"]["noDriverNearby"] = obj({
    "on": {**b(), "default": NDD["noDriverNearby"]["on"]},
    "afterSec": {**i("Seconds from search start (live rides).", minimum=NDR["afterSec"][0], maximum=NDR["afterSec"][1]), "default": NDD["noDriverNearby"]["afterSec"]},
    "message": {**s(minLength=1, maxLength=300), "default": NDD["noDriverNearby"]["message"]},
}, ["on", "afterSec"], "v0.18.39 §63: " + ND["message"] + " " + ND["liveNoEnd"])
S["DispatchDocument"]["properties"]["limits"]["properties"]["farReachKm"] = {
    **n("v0.18.39 §63: " + ND["farReach"], exclusiveMinimum=NDR["farReachKm"][0], maximum=NDR["farReachKm"][1]), "default": NDD["farReachKm"]}
S["DriverReservations"]["properties"]["noDriverStopAfterMin"] = dflt(
    i("v0.18.39 §63 (P17): " + ND["bookedStop"], minimum=NDR["noDriverStopAfterMin"][0], maximum=NDR["noDriverStopAfterMin"][1]), NDD["noDriverStopAfterMin"])
S["SearchStep"]["properties"]["kind"] = s(enum=ND["searchStepKinds"])
S["SearchStep"]["description"] += " v0.18.39 §63: no_driver_nearby (" + ND["riderAnswer"] + ") and no_driver_found (" + ND["bookedStop"] + ")."
_KW = PATHS["/trips/{tripId}/keep-waiting"]["post"]
_KW["description"] += " v0.18.39 §63: " + ND["riderAnswer"] + " " + ND["liveNoEnd"]
# ReservationInfo is defined in 0600; its v0.18.39 field noDriverFound is added there (one line, after the definition).
S["DispatchDocument"]["properties"]["reaskLimit"] = {**i("v0.18.39 §63: " + ND["reaskLimit"], minimum=NDR["reaskLimit"][0], maximum=NDR["reaskLimit"][1]), "default": NDD["reaskLimit"]}
