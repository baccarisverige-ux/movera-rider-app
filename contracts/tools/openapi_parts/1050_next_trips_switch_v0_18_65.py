# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.65 §86: the trip radar's
# "stop next trips" reaches the server (contract.json#nextTripsSwitch).
_NT = C["nextTripsSwitch"]
S["NextTripsRequest"] = obj({"on": b("false: no next-trip offers during this trip; true: they come again.")}, ["on"])
S["Driver"]["properties"]["nextTripsOff"] = {**b("v0.18.65 §86: he stopped next-trip offers on the trip sheet's radar for his current trip. " + _NT["noOffers"] + " " + _NT["end"]), "default": False}
S["LiveDriver"]["properties"]["nextTripsOff"] = b("v0.18.65 §86: on a trip with next-trip offers stopped. " + _NT["admin"])
op("post", "/driver/next-trips", "setDriverNextTrips", "Stop / start next-trip offers during a trip", ["driver"], "Driver · Session",
   body="NextTripsRequest", ok=(200, "Driver"), mutation=True,
   desc="v0.18.65 §86: " + " ".join(_NT[k] for k in ("route", "noOffers", "end", "restart")))
