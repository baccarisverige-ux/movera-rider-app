# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.128 (S7 W2 Q125, plan B3.11;
# owner 2026-11-15 Sitting W2 Q125 (Q-B3) "A) count and log above N = 3, refuse later"; Rules decisions/session-2026-11-06.md:1388):
# wording only, no shape change. The app streams say that a session's streams above 3 per server copy are logged and
# counted, not refused; the text comes from contract.json#realtime.appStreamsPerSession.
_ASP = C["realtime"]["appStreamsPerSession"]
for _path in ["/rider/config/stream", "/driver/config/stream", "/driver/offers/stream"]:
    _o = PATHS[_path]["get"]
    assert "v0.18.128" not in _o.get("description", ""), _path + " v0.18.128 text exists before"
    _o["description"] = (_o.get("description", "") + " v0.18.128 (contract.json#realtime.appStreamsPerSession): more than "
                         + str(_ASP["limit"]) + " open app streams of one session on a server copy are logged and counted, never refused in this version.").strip()
