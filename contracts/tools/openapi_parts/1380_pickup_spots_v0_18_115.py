# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.115 (BQ-V21, owner full-audit
# Q6 2026-11-02 "Keep as 'approximate'" => admin on/off per zone (default on), Rules decisions/rider-g4-pickup.md:7):
# RiderAppConfig.booking.pickupSpots.on, the zone's switch for the rider's approximate pickup entrance chips
# (contract.json#pickupSpots). Rider document only; the driver document gets nothing.
_PS = C["pickupSpots"]
_RB = S["RiderAppConfig"]["properties"]["booking"]["properties"]
assert "pickupSpots" not in _RB, "RiderAppConfig.booking.pickupSpots exists before v0.18.115"
assert "pickupSpots" not in S["DriverAppConfig"]["properties"]["booking"]["properties"], "driver booking has no pickupSpots"
_RB["pickupSpots"] = obj({"on": {**b(_PS["rider"]), "default": C["configDefaults"]["pickupSpotsOn"]}},
                         desc=_PS["note"] + " " + _PS["setting"] + " " + _PS["server"])
