# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.105 (BQ-V43, G4 decision 1,
# owner R7, Rules decisions/driver-g4.md:2, driver-g2.md:61): GET /push/config?platform=android gives the Firebase
# Android app's public settings (androidConfig) so the driver's Android store build keeps no google-services.json.
PA = AU["devices"]["config"]["android"]
_V105 = "v0.18.105: "
S["PushConfig"]["properties"]["androidConfig"] = {"allOf": [ref("PushWebConfig")], "description": _V105 + "only with platform=android. " + PA["note"]}
PATHS["/push/config"]["get"]["parameters"].append({"name": "platform", "in": "query", "required": False,
    "description": _V105 + "web (default) gives webConfig, android gives androidConfig, ios is enabled false for now. " + PA["ios"],
    "schema": s(enum=PA["platforms"])})
PATHS["/push/config"]["get"]["description"] += " " + _V105 + PA["appStart"]
