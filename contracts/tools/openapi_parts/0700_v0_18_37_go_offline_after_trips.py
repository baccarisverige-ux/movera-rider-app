# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.37 §61 go offline after trips.
# v0.18.37 §61 (contract.json#goOfflineAfterTrips): go offline after trips.
GOA = C["goOfflineAfterTrips"]
S["Driver"]["properties"]["offlineAfterTrip"] = {**b("v0.18.37 §61: he tapped Go offline during a trip; he goes offline when his last trip ends. " + GOA["tap"] + " " + GOA["end"]), "default": False}
S["Driver"]["properties"]["offlineAfterTripSince"] = {"oneOf": [ref("Timestamp"), {"type": "null"}], "description": "v0.18.37 §61: when he tapped Go offline during the trip (null without offlineAfterTrip)."}
S["LiveDriver"]["properties"]["offlineAfterTrip"] = b("v0.18.37 §61: on a trip and going offline when his trips end (admin label 'Going offline after trips'). " + GOA["admin"])
PATHS["/driver/availability"]["post"]["description"] += " v0.18.37 §61 (go offline after trips): offline while on a trip is no longer 409 on_trip: " + GOA["tap"] + " " + GOA["undo"] + " " + GOA["noOffers"]
