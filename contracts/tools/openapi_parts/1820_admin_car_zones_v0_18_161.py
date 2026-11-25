# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.161 (owner 2026-11-25 "Yes, fix it":
# the admin mixed French and Swedish cars): GET /admin/vehicles and GET /admin/fleets take zoneId, zoneIds and country like
# the other admin lists, total under the same filter; Vehicle.zoneId / Vehicle.country and Fleet.zoneId
# (contract.json#adminListFilters.carZones).
_CZ = C["adminListFilters"]["carZones"]
_V161 = "v0.18.161 (adminListFilters.carZones): "
for _path in ("/admin/vehicles", "/admin/fleets"):
    _op = PATHS[_path]["get"]
    _ps = [p for p in _op["parameters"] if p not in (pref("ZoneIdQuery"), pref("ListZoneId"), pref("ListZoneIds"), pref("ListCountry")) and p.get("name") != "country"]
    _at = next(k for k, p in enumerate(_ps) if p == pref("Q"))
    _op["parameters"] = _ps[:_at] + [pref("ListZoneId"), pref("ListZoneIds"), pref("ListCountry")] + _ps[_at:]
    _op["description"] += " " + _V161 + _CZ["note"] + ZF_DESC + " " + _CZ["existingZoneId"]
    _op.setdefault("responses", {})["403"] = rref("Forbidden")
PATHS["/admin/vehicles"]["get"]["description"] += " " + _CZ["carZone"] + " " + _CZ["noZone"]
PATHS["/admin/fleets"]["get"]["description"] += " " + _CZ["fleetZone"]
S["Vehicle"]["properties"]["zoneId"] = {"oneOf": [ref("Id"), {"type": "null"}], "description": _V161 + "the car's zone: " + _CZ["carZone"] + " Admin views only; absent from an older server."}
S["Vehicle"]["properties"]["country"] = {"oneOf": [ref("CountryCode"), {"type": "null"}], "description": _V161 + "the car's country: its fleet's country, else its driver's country, else null (shown as unknown, never guessed). Admin views only; absent from an older server."}
S["Fleet"]["properties"]["zoneId"] = {"allOf": [ref("Id")], "description": _V161 + _CZ["fleetZone"] + " Absent from an older server."}
