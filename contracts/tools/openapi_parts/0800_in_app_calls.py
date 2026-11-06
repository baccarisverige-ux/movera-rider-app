# v0.18.38 §62 (fix job 8, contract.json#inAppCalls): in-app (WebRTC) calls between the trip's rider and driver.
# Run by tools/gen_openapi.py in name order with its globals (rule 25 split).
IC = C["inAppCalls"]
ICD = C["configDefaults"]["calls"]
ICR = IC["settings"]["ranges"]
S["TripCall"]["description"] = "v0.13.0: a masked call between the trip's rider and driver (contract.json#chat.call). v0.18.38 §62: " + IC["start"] + " " + IC["phoneMode"]
S["TripCall"]["required"] = ["tripId", "expiresAt"]
S["TripCall"]["properties"]["proxyNumber"] = s("v0.13.0: the masked number to dial (E.164); the provider bridges to the other side. v0.18.38: mode phone only.", pattern=r"^\+[1-9][0-9]{6,14}$")
S["IceServer"] = obj({"urls": arr(s(), minItems=1), "username": s(), "credential": s()}, ["urls"], "v0.18.38: " + IC["ice"])
S["TripCall"]["properties"]["mode"] = s("v0.18.38: in_app (WebRTC, default) or phone (proxyNumber).", enum=["in_app", "phone"])
S["TripCall"]["properties"]["callId"] = {"allOf": [ref("Id")], "description": "v0.18.38, mode in_app."}
S["TripCall"]["properties"]["ice"] = obj({"servers": arr(ref("IceServer")), "ttlSeconds": i(minimum=0)}, ["servers", "ttlSeconds"], "v0.18.38, mode in_app: " + IC["ice"])
S["TripCall"]["properties"]["ringSeconds"] = i("v0.18.38, mode in_app.", minimum=ICR["ringSeconds"][0], maximum=ICR["ringSeconds"][1])
S["TripCall"]["properties"]["maxCallMin"] = i("v0.18.38, mode in_app.", minimum=ICR["maxCallMin"][0], maximum=ICR["maxCallMin"][1])
S["CallState"] = s("v0.18.38.", enum=["ringing", "answered", "ended", "missed"])
S["CallView"] = obj({"callId": ref("Id"), "tripId": ref("Id"), "from": s(enum=IC["who"]), "to": s(enum=IC["who"]), "state": ref("CallState"),
                     "startedAt": ref("Timestamp"), "answeredAt": nullable("Timestamp"), "endedAt": nullable("Timestamp"),
                     "endedReason": {"oneOf": [s(enum=IC["endedReasons"]), {"type": "null"}]}, "seconds": i("Talk time (answered → ended); 0 when never answered.", minimum=0)},
                    ["callId", "tripId", "from", "to", "state", "startedAt", "answeredAt", "endedAt", "endedReason", "seconds"], "v0.18.38: " + IC["noPhoneNumbers"])
S["CallView"]["properties"]["ice"] = {"allOf": [S["TripCall"]["properties"]["ice"]], "description": "v0.18.38: on the answer of POST /calls/{callId}/answer only: the callee's ICE servers."}
S["CallSignal"] = obj({"type": s(enum=["offer", "answer", "ice"]), "sdp": s(maxLength=20000), "candidate": obj({"candidate": s(maxLength=2000), "sdpMid": {"oneOf": [s(), {"type": "null"}]}, "sdpMLineIndex": {"oneOf": [i(minimum=0), {"type": "null"}]}}, ["candidate"])},
                      ["type"], "v0.18.38: " + IC["signalling"])
S["CallSignalEvent"] = obj({"callId": ref("Id"), "from": s(enum=IC["who"]), "type": s(enum=["offer", "answer", "ice"]), "sdp": s(), "candidate": S["CallSignal"]["properties"]["candidate"]}, ["callId", "from", "type"])
S["CallEndRequest"] = obj({"reason": s(enum=["hangup", "declined", "failed"])}, ["reason"], "v0.18.38: " + IC["end"])
S["CallLog"] = obj({"items": arr(ref("CallView"))}, ["items"], "v0.18.38: " + IC["adminLog"])
S["RealtimeEvent"]["properties"]["call"] = {"allOf": [ref("CallView")], "description": "v0.18.38: on call_ringing, call_answered, call_ended, call_missed."}
S["RealtimeEvent"]["properties"]["signal"] = {"allOf": [ref("CallSignalEvent")], "description": "v0.18.38: on call_signal."}
S["CountryRules"]["properties"]["calls"] = obj({"on": {**b(IC["settings"]["off"]), "default": ICD["on"]},
                                                "mode": {**s(IC["phoneMode"], enum=["in_app", "phone"]), "default": ICD["mode"]},
                                                "callWindowAfterTripMin": {**i(IC["window"], minimum=ICR["callWindowAfterTripMin"][0], maximum=ICR["callWindowAfterTripMin"][1]), "default": ICD["callWindowAfterTripMin"]},
                                                "ringSeconds": {**i(IC["missed"], minimum=ICR["ringSeconds"][0], maximum=ICR["ringSeconds"][1]), "default": ICD["ringSeconds"]},
                                                "maxCallMin": {**i(minimum=ICR["maxCallMin"][0], maximum=ICR["maxCallMin"][1]), "default": ICD["maxCallMin"]},
                                                "adminCallRoles": {**arr(s()), "default": ICD["adminCallRoles"]},
                                                "phoneProvider": {**s(enum=["none", "twilio"]), "default": ICD["phoneProvider"]}}, [],
                                               "v0.18.38 §62: " + IC["settings"]["where"])
CID = [{"name": "callId", "in": "path", "required": True, "schema": ref("Id")}]
op("post", "/calls/{callId}/signal", "callSignal", "Relay a WebRTC offer / answer / ICE candidate (emits call_signal)", ["rider", "driver"], "Notifications & messages",
   params=CID, body="CallSignal", ok=(202, None), mutation=True, desc="v0.18.38: " + IC["signalling"] + " Not live: 409 invalid_transition, reason call_not_live.")
op("post", "/calls/{callId}/answer", "callAnswer", "Answer a ringing call (emits call_answered)", ["rider", "driver"], "Notifications & messages",
   params=CID, body="EmptyCommand", ok=(200, "CallView"), mutation=True, desc="v0.18.38: " + IC["answer"])
op("post", "/calls/{callId}/end", "callEnd", "End, decline or report a failed call (emits call_ended)", ["rider", "driver"], "Notifications & messages",
   params=CID, body="CallEndRequest", ok=(200, "CallView"), mutation=True, desc="v0.18.38: " + IC["end"])
op("get", "/admin/trips/{tripId}/calls", "adminTripCalls", "The trip's call log (no audio, no numbers)", ["admin"], "Admin · Trips",
   params=TID, ok=(200, "CallLog"), permission="trips.read", desc="v0.18.38: " + IC["adminLog"])
PATHS["/trips/{tripId}/call"]["post"]["description"] = "v0.18.38 §62: " + IC["start"] + " " + IC["window"] + " " + IC["busy"] + " " + IC["settings"]["off"] + " " + IC["phoneMode"]

