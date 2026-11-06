# v0.18.44 §67 (same-address fix, contract.json#sameAddress): geocode by placeId answers the place name; pricing.minTripMeters; dropoff_too_close.
# A part of tools/gen_openapi.py (rule 25 split), run in name order with its globals, after 0200 defines the ops.
SA = C["sameAddress"]
MT = SA["minTripMeters"]
S["GeocodeRequest"]["properties"]["placeId"] = s("v0.18.44 §67: the picked suggestion's placeId; the server resolves by it. " + SA["geocode"])
S["GeocodeResult"]["properties"]["name"] = s("v0.18.44 §67: the place's own name when resolved by placeId (absent for a typed address). " + SA["label"])
S["PricingDocument"]["properties"]["minTripMeters"] = {**i("v0.18.44 §67: " + MT["where"] + "; " + MT["measure"] + ". " + SA["refuse"], minimum=MT["range"][0], maximum=MT["range"][1]), "default": MT["default"]}
for _path in ("/quotes", "/trips"):
    PATHS[_path]["post"]["description"] = (PATHS[_path]["post"].get("description", "") + " v0.18.44 §67: " + SA["refuse"]).strip()
PATHS["/locations/geocode"]["post"]["description"] += " v0.18.44 §67: " + SA["geocode"]
