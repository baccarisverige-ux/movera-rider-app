# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.150 (L20 stream backup; owner
# 2026-11-21 "Switch to old two (Rec.)", Rules plan/NUMBERS.md): DriverAppConfig.realtime.oneStreamFallback
# { failuresInARow 1-10 default 3, retryOneAfterMinutes 1-60 default 10 } (contract.json#driverOneStreamFallback): after
# that many failed tries of GET /driver/stream in a row the driver app opens the two old streams for that many minutes.
# Additive: one optional object; the routes are unchanged (texts only). The kept key lands in removeKeys via part 1500.
_FB = C["driverOneStreamFallback"]
_FBD = C["configDefaults"]["driverOneStreamFallback"]
_RT = S["DriverAppConfig"]["properties"]["realtime"]
assert "oneStreamFallback" not in _RT["properties"], "realtime.oneStreamFallback exists before v0.18.150"
_RT["properties"]["oneStreamFallback"] = obj({
    "failuresInARow": i("Failed tries of GET /driver/stream in a row before the app opens the two old streams. " + _FB["failedTry"], minimum=1, maximum=10, default=_FBD["failuresInARow"]),
    "retryOneAfterMinutes": i("Minutes on the two old streams before the next reconnect asks GET /driver/stream again (or at app restart).", minimum=1, maximum=60, default=_FBD["retryOneAfterMinutes"]),
}, desc="v0.18.150 (contract.json#driverOneStreamFallback): " + " ".join(_FB[k] for k in ("note", "setting", "driver", "admin")), addl=False)
PATHS["/driver/stream"]["get"]["description"] += " v0.18.150 (driverOneStreamFallback): " + _FB["failedTry"] + " " + _FB["driver"]
PATHS["/admin/config/{doc}"]["put"]["description"] += " v0.18.150 (driverOneStreamFallback.server): " + _FB["server"]
