# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.160 (free pickup move 300 m;
# owner 2026-11-23, Rules decisions/session-2026-11-06.md): the pickup move default is 300 m (was 200), range 0-2000.
_PM160 = C["pickupWaiting"]["pickupMove"]
assert _PM160["default"] == 300, "pickupMove default 300 from v0.18.160"
for _cfg in ("RiderAppConfig", "DriverAppConfig"):
    S[_cfg]["properties"]["booking"]["properties"]["maxPickupMoveMeters"]["description"] += " v0.18.160: default 300 (was 200; the rider moves the pickup up to 300 m for free); " + _PM160["freeMoveNote"]
