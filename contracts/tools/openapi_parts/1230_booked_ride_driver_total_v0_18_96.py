# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.96 (BQ-M23; owner 2026-11-12,
# Rules decisions/session-2026-11-06.md:1164 "on the offer when come he see only how much he get"): a booked ride in the
# driver's lists carries what he gets (contract.json#priceDisplay.bookedRide). Additive field only.
_BR = C["priceDisplay"]["bookedRide"]
_R = S["DriverReservation"]["properties"]
assert "driverTotal" not in _R, "DriverReservation.driverTotal exists before v0.18.96"
_R["driverTotal"] = {"allOf": [ref("Money")], "description": "v0.18.96: " + _BR["driverTotal"] + " " + _BR["apps"]["driver"]}
_R["earnings"] = {"allOf": [ref("Money")], "description": "v0.18.96: the trip's driverEarnings line, without Movera's bonus and pickup pay; not shown to the driver (he sees driverTotal)."}
