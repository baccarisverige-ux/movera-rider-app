# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.72 §89 (G17): the driver's
# config and its stream follow the zone he works in (contract.json#driverConfigZone). pref("ZoneIdQuery") renders as a
# plain $ref, so the two driver operations get their own zoneId parameter in its place (the rider keeps the shared one).
_DCZ = C["driverConfigZone"]
_ZQ = pref("ZoneIdQuery")
for _p in ("/driver/config", "/driver/config/stream"):
    _op = PATHS[_p]["get"]
    _op["description"] = (_op.get("description", "") + " v0.18.72 §89 (G17): " + _DCZ["note"] + " " + _DCZ["app"] + " "
                          + _DCZ["serverDefault"] + " " + _DCZ["asked"]).strip()
    assert _ZQ in _op["parameters"], _p + " lost ZoneIdQuery"
    _op["parameters"] = [p if p != _ZQ else
                         {"name": "zoneId", "in": "query", "required": False, "schema": ref("Id"),
                          "description": "v0.18.72 §89: the zone the driver works in (his active trip's zone, else the zone of his position). "
                                         "Without it: the active trip's zone, else the latest fix's zone, else Driver.zoneIds[0], else the server default zone."}
                         for p in _op["parameters"]]
