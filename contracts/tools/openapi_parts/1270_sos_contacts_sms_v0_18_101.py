# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.101 §92 (BQ-V34, owner
# 2026-11-02 Q2 "Use them in SOS", Rules decisions/driver-g14.md:12): the driver's SOS texts his emergency contacts.
SCS = C["sosContactsSms"]
_V101 = "v0.18.101 §92: "
S["SosContactsSms"] = obj(OrderedDict([
    ("status", s(enum=SCS["statuses"])),
    ("contacts", i("SMS asked for (one per stored contact).", minimum=0)),
    ("sent", i("Accepted by the SMS company; only for sent / failed.", minimum=0)),
    ("at", ref("Timestamp")),
]), ["status", "contacts", "at"], _V101 + SCS["result"] + " " + SCS["delivery"])
S["SosReceipt"]["properties"]["contactsSms"] = {"allOf": [ref("SosContactsSms")], "description": _V101 + "driver SOS only; " + SCS["when"]}
S["Incident"]["properties"]["contactsSms"] = {"allOf": [ref("SosContactsSms")], "description": _V101 + "the SMS to the driver's emergency contacts of this case (admin views and feed)."}
S["CountryRules"]["properties"]["sosContactsSms"] = {**b(_V101 + SCS["setting"]), "default": True}
S["DriverAppConfig"]["properties"]["sosContactsSms"] = obj({"on": b("The zone country's switch."), "connected": b("An SMS company is connected on this server.")},
                                                           ["on", "connected"], _V101 + SCS["driverConfig"])
