# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.129 (saved-places design,
# owner 2026-11-18 "Build", Rules decisions/session-2026-11-18-saved-places-design.md steps 4-7): a saved place may
# carry one fixed ride category (contract.json#phoneDataToServer.riderPlaces.preferredCategory). Additive.
_PC = C["phoneDataToServer"]["riderPlaces"]["preferredCategory"]
_V129 = "v0.18.129 (contract.json#phoneDataToServer.riderPlaces.preferredCategory): "
for _n in ("SavedPlace", "SavedPlaceRequest"):
    assert "preferredCategoryId" not in S[_n]["properties"], _n + ".preferredCategoryId exists before v0.18.129"
_props = OrderedDict(S["SavedPlace"]["properties"])
_props["preferredCategoryId"] = {"description": _V129 + _PC["field"] + " " + _PC["check"], **nullable("CategoryId")}
S["SavedPlace"]["properties"] = _props
# SavedPlaceRequest shared _SP with SavedPlace; give it its own copy with the optional field.
_rprops = OrderedDict(S["SavedPlaceRequest"]["properties"])
_rprops["preferredCategoryId"] = {"description": _V129 + _PC["write"] + " " + _PC["check"], **nullable("CategoryId")}
S["SavedPlaceRequest"]["properties"] = _rprops
for _p, _m in (("/rider/places", "post"), ("/rider/places/{placeId}", "put"), ("/rider/places/import", "post")):
    PATHS[_p][_m]["description"] = PATHS[_p][_m].get("description", "") + " " + _V129 + _PC["write"] + " " + _PC["check"]
