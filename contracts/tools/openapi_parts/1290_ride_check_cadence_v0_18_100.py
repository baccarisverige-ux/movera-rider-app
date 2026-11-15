# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.100 (BQ-V37, owner W1 Q66 "Yes"
# = Q-B6, Rules audits/impact/v37-ridecheck-cadence.md): the server's ride-check scan runs at most once every
# DriverAppConfig.rideCheck.scanEverySeconds per trip (per zone, default 30 s, 10-60; owner 2026-11-15: at most 60 s). Additive.
_RC100 = C["onTrip"]["rideCheck"]
_RCR100 = _RC100["settings"]["ranges"]["scanEverySeconds"]
S["RideCheck"]["properties"]["scanEverySeconds"] = {
    **i("v0.18.100: " + _RC100["settings"]["fields"]["scanEverySeconds"] + " " + _RC100["detection"]["cadence"], minimum=_RCR100[0], maximum=_RCR100[1]),
    "default": C["configDefaults"]["rideCheck"]["scanEverySeconds"],
}
