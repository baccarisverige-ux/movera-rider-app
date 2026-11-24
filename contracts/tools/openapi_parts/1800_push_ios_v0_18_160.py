# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.160 (owner 2026-11-24
# "Notifications doesn't work on iPhones?"): GET /push/config?platform=ios gives the Firebase iOS app's public settings
# (iosConfig) so the iPhone apps keep no GoogleService-Info.plist, and every FCM message carries an apns block. Additive.
_PI = AU["devices"]["config"]["ios"]
_V160 = "v0.18.160: "
assert "iosConfig" not in S["PushConfig"]["properties"], "PushConfig.iosConfig exists before v0.18.160"
S["PushIosConfig"] = obj({"apiKey": s("Public Firebase iOS API key (not a secret)."), "appId": s("The Firebase iOS app id (1:<sender>:ios:<id>).", pattern=":ios:"),
                          "messagingSenderId": s(), "projectId": s(), "iosBundleId": s(enum=sorted(set(_PI["iosBundleIds"].values())))},
                         ["apiKey", "appId", "messagingSenderId", "projectId", "iosBundleId"], _V160 + "the Firebase iOS app's public settings. " + _PI["note"])
S["PushConfig"]["properties"]["iosConfig"] = {"allOf": [ref("PushIosConfig")], "description": _V160 + "only with platform=ios. " + _PI["note"]}
_pp = next(p for p in PATHS["/push/config"]["get"]["parameters"] if p.get("name") == "platform")
_pp["description"] += " " + _V160 + "ios gives iosConfig (enabled true once the project has the iOS app). " + _PI["appStart"]
PATHS["/push/config"]["get"]["description"] += " " + _V160 + _PI["appStart"] + " " + _PI["apps"]
PATHS["/push/devices"]["post"]["description"] += " " + AU["devices"]["sending"]["apns"]
