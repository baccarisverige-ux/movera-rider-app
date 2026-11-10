# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.56 §78 (G9 part 2, owner Q79–Q85): chat & calls.
CH = C["chat"]
CHD = C["configDefaults"]["chat"]
CHR = CH["settings"]["ranges"]
CHF = CH["settings"]["fields"]
IC56 = C["inAppCalls"]
_V = "v0.18.56 §78: "
_L3 = lambda mx: obj({"sv": s(minLength=1, maxLength=mx), "fr": s(minLength=1, maxLength=mx), "en": s(minLength=1, maxLength=mx)}, ["sv", "fr", "en"])
S["QuickReply"] = obj({"id": s(pattern="^[a-z][a-z0-9_]{0,39}$"), "text": _L3(CHR["quickReplyTextLength"][1])}, ["id", "text"], _V + CH["quickReplies"]["note"])
_QRL = arr(ref("QuickReply"), maxItems=CHR["quickRepliesPerSide"][1])
S["ChatSettings"] = obj({
    "keepDays": {**i(CHF["keepDays"], minimum=CHR["keepDays"][0], maximum=CHR["keepDays"][1]), "default": CHD["keepDays"]},
    "maxLength": {**i(CHF["maxLength"], minimum=CHR["maxLength"][0], maximum=CHR["maxLength"][1]), "default": CHD["maxLength"]},
    "spamPerMin": {**i(CHF["spamPerMin"], minimum=CHR["spamPerMin"][0], maximum=CHR["spamPerMin"][1]), "default": CHD["spamPerMin"]},
    "sound": {**b(CHF["sound"]), "default": CHD["sound"]},
    "sheetAutoOpen": {**s(CHF["sheetAutoOpen"], enum=CH["settings"]["sheetAutoOpenValues"]), "default": CHD["sheetAutoOpen"]},
    "readAloudDefault": {**b(CHF["readAloudDefault"]), "default": CHD["readAloudDefault"]},
    "translation": {**b(CHF["translation"]), "default": CHD["translation"]},
    "quickRepliesOn": {**b(CHF["quickRepliesOn"]), "default": CHD["quickRepliesOn"]},
    "quickReplies": {**obj({"driver": _QRL, "rider": _QRL}, ["driver", "rider"], CHF["quickReplies"]), "default": CHD["quickReplies"]},
    "autoArrived": {**obj({"on": b(), "text": _L3(200)}, ["on", "text"], CHF["autoArrived"]), "default": CHD["autoArrived"]}},
    [], _V + CH["settings"]["where"])
S["CountryRules"]["properties"]["chat"] = ref("ChatSettings")
S["ChatOptions"] = obj({"quickReplies": arr(ref("QuickReply")), "quickRepliesOn": b(), "maxLength": i(minimum=1, maximum=2000), "sound": b(),
                        "sheetAutoOpen": s(enum=CH["settings"]["sheetAutoOpenValues"]), "readAloudDefault": b(), "translation": b(),
                        "headerLine": _L3(200)},
                       ["quickReplies", "quickRepliesOn", "maxLength", "sound", "sheetAutoOpen", "readAloudDefault", "translation", "headerLine"],
                       _V + CH["settings"]["apps"] + " " + CH["header"]["note"])
S["MessageRequest"]["properties"]["quickReplyId"] = s(_V + CH["quickReplies"]["send"], pattern="^[a-z][a-z0-9_]{0,39}$")
S["Message"]["properties"]["quickReplyId"] = s(_V + "set when the message was sent from a quick-reply chip.")
S["Message"]["properties"]["auto"] = s(_V + CH["autoArrived"]["when"] + " " + CH["autoArrived"]["language"] + " " + CH["onTheWay"]["when"], enum=["arrived", "on_my_way"])
S["TranslateMessageRequest"] = obj({"messageId": ref("Id"), "to": s(enum=["sv", "fr", "en"])}, ["messageId", "to"], _V + CH["translate"]["route"])
S["TranslatedMessage"] = obj({"messageId": ref("Id"), "to": s(enum=["sv", "fr", "en"]), "text": s(minLength=1)}, ["messageId", "to", "text"], _V + "nothing is stored.")
S["AdminChatRow"] = obj({"tripId": ref("Id"), "zoneId": ref("Id"), "status": ref("TripStatus"), "riderFirstName": {"type": ["string", "null"]},
                         "driverFirstName": {"type": ["string", "null"]}, "messageCount": i(minimum=1), "lastMessageAt": ref("Timestamp"),
                         "lastFrom": s(enum=["rider", "driver", "support"])},
                        ["tripId", "zoneId", "status", "messageCount", "lastMessageAt", "lastFrom"], _V + CH["adminChats"]["row"])
S["AdminChatPage"] = obj({"items": arr(ref("AdminChatRow")), "nextCursor": {"type": ["string", "null"]}}, ["items", "nextCursor"], _V + CH["adminChats"]["route"])
S["AdminPersonMessageCommand"] = obj({"text": s(minLength=1, maxLength=2000)}, ["text"], _V + CH["adminMessage"]["route"])

op("get", "/trips/{tripId}/messages/options", "tripChatOptions", "Chat options of the trip: quick replies and chat settings", ["rider", "driver"], "Notifications & messages",
   params=TID, ok=(200, "ChatOptions"), desc=_V + CH["settings"]["apps"])
op("post", "/trips/{tripId}/messages/translate", "translateTripMessage", "Translate one chat message (503 coming_soon until a provider is set)", ["rider", "driver"], "Notifications & messages",
   params=TID, body="TranslateMessageRequest", ok=(200, "TranslatedMessage"), desc=_V + CH["translate"]["route"] + " " + CH["translate"]["target"])
op("get", "/admin/chats", "adminChats", "Open trips with chat messages (live chat list)", ["admin"], "Admin · Support",
   params=[pref("ListZoneId"), pref("ListZoneIds"), pref("ListCountry"), pref("Cursor"), pref("Limit")], ok=(200, "AdminChatPage"), permission="support.reply",
   desc=_V + CH["adminChats"]["route"] + " " + CH["adminChats"]["row"])
op("post", "/admin/drivers/{driverId}/message", "adminMessageDriver", "Message a driver in the app's Support inbox", ["admin"], "Admin · Support",
   params=[pref("DriverId")], body="AdminPersonMessageCommand", ok=(201, "SupportTicket"), mutation=True, permission="support.reply",
   desc=_V + CH["adminMessage"]["route"] + " " + CH["adminMessage"]["push"])
op("post", "/admin/riders/{riderId}/message", "adminMessageRider", "Message a rider in the app's Support inbox", ["admin"], "Admin · Support",
   params=[pref("RiderId")], body="AdminPersonMessageCommand", ok=(201, "SupportTicket"), mutation=True, permission="support.reply",
   desc=_V + CH["adminMessage"]["route"] + " " + CH["adminMessage"]["push"])
_m = PATHS["/trips/{tripId}/messages"]
_m["get"]["description"] += " " + _V + CH["stream"]["badge"] + " " + CH["stream"]["gate"]
_m["post"]["description"] += " " + _V + CHF["maxLength"] + " " + CHF["spamPerMin"] + " " + CH["quickReplies"]["send"]
PATHS["/trips/{tripId}/arrive"]["post"]["description"] += " " + _V + CH["autoArrived"]["when"] + " " + CH["autoArrived"]["language"] + " " + CH["autoArrived"]["off"]
PATHS["/trips/{tripId}/call"]["post"]["description"] += " " + _V + IC56["push"]["when"] + " " + IC56["push"]["iphone"] + " " + IC56["background"]["rule"] + " Server environment names: " + ", ".join(IC56["turnEnv"]["names"]) + "."
PATHS["/trips/{tripId}/on-the-way"]["post"]["description"] += " " + _V + CH["onTheWay"]["when"]
S["TranslateMessageRequest"]["description"] += " " + CH["translate"]["target"]
