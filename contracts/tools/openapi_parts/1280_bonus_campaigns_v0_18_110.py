# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.110 (BQ-V44; owner G10-5 "Make
# bonuses real (Recommended)", Rules decisions/driver-g10.md:9; Q12 bonus zones, decisions/admin-fake-by-group.md:40):
# bonus campaigns (contract.json#bonusCampaigns). Additive only. Not the trip bonus (adminDispatch.driverBonus).
_BC = C["bonusCampaigns"]
_V = "v0.18.110: "
assert "BonusCampaign" not in S and "/admin/bonuses" not in PATHS, "bonus campaigns exist before v0.18.110"
_L = _BC["limits"]
_DATE = s("Local date YYYY-MM-DD in the zone's time zone.", pattern="^\\d{4}-\\d{2}-\\d{2}$")
_T = _L["target"]
S["BonusMeasure"] = s(_V + "trips = trips with a paid end whose pickup is inside the area; online_hours = time online (or on a trip) inside the area. "
                      + _BC["counting"]["trips"] + " " + _BC["counting"]["onlineHours"], enum=_BC["measures"])
S["BonusState"] = s(_V + _BC["window"], enum=_BC["states"])
S["BonusProgressNumbers"] = obj({"done": i("Trips counted, or whole minutes online counted (online_hours).", minimum=0),
                                 "target": i("The target in the same unit: trips, or target hours × 60 minutes.", minimum=1)},
                                ["done", "target"], _V + "the server's numbers; the apps show them and never work progress out.")
S["BonusCampaign"] = obj(OrderedDict([
    ("bonusId", ref("Id")), ("zoneId", ref("Id")), ("country", ref("CountryCode")), ("currency", ref("CurrencyCode")),
    ("timeZone", s("The zone's IANA time zone.")), ("names", ref("ZoneNames")), ("measure", ref("BonusMeasure")),
    ("target", i(f"trips {_T['trips'][0]}-{_T['trips'][1]}, online_hours {_T['online_hours'][0]}-{_T['online_hours'][1]} (hours).", minimum=1)),
    ("amount", money("Paid once to each driver who reaches the target; the zone's currency. " + _L["amount"])),
    ("startDate", _DATE), ("endDate", _DATE),
    ("polygon", {"allOf": [ref("ZonePolygon")], "description": _L["polygon"]}), ("bounds", ref("ZoneBounds")),
    ("status", s("Stored status.", enum=_BC["statuses"])), ("state", ref("BonusState")), ("version", i(minimum=1)),
    ("createdAt", ref("Timestamp")), ("createdBy", ref("Id")), ("updatedAt", ref("Timestamp")), ("endedAt", ref("Timestamp")),
    ("driversWithProgress", i("Drivers with any progress.", minimum=0)), ("driversEarned", i("Drivers who earned it.", minimum=0)),
    ("paidTotal", money("The sum of the campaign's earnings entries (amount × driversEarned)."))]),
    ["bonusId", "zoneId", "country", "currency", "timeZone", "names", "measure", "target", "amount", "startDate", "endDate", "polygon", "bounds",
     "status", "state", "version", "createdAt", "createdBy", "updatedAt", "driversWithProgress", "driversEarned", "paidTotal"],
    _V + _BC["note"] + " " + _BC["award"] + " " + _BC["permissions"])
S["BonusCampaignCreate"] = obj(OrderedDict([("zoneId", ref("Id")), ("names", ref("ZoneNames")), ("measure", ref("BonusMeasure")),
                                            ("target", i(minimum=1)), ("amount", ref("Money")), ("startDate", _DATE), ("endDate", _DATE),
                                            ("polygon", ref("ZonePolygon"))]),
                               ["zoneId", "names", "measure", "target", "amount", "startDate", "endDate", "polygon"],
                               _V + _BC["endpoints"]["adminCreate"] + " " + _L["dates"] + " Errors: " + ", ".join(_BC["errors"]["400"]) + ".", addl=False)
S["BonusCampaignUpdate"] = obj({**EV, "names": ref("ZoneNames"), "endDate": _DATE}, ["expectedVersion"], _V + _BC["endpoints"]["adminUpdate"], addl=False)
S["BonusCampaignCommand"] = obj(dict(EV), ["expectedVersion"], _V + _BC["endpoints"]["adminPause"], addl=False)
S["BonusCampaignPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("BonusCampaign"))}}], "description": _V + "Page<BonusCampaign>, newest first."}
S["BonusProgress"] = obj({"driverId": ref("Id"), "firstName": s(), "progress": ref("BonusProgressNumbers"), "earned": b(), "earnedAt": ref("Timestamp"), "entryId": ref("Id")},
                         ["driverId", "firstName", "progress", "earned"], _V + "one driver's progress in a campaign (admin view).")
S["BonusProgressPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("BonusProgress"))}}], "description": _V + "Page<BonusProgress>, most progress first."}
S["DriverBonus"] = obj(OrderedDict([("bonusId", ref("Id")), ("names", ref("ZoneNames")), ("measure", ref("BonusMeasure")), ("state", ref("BonusState")),
                                    ("startDate", _DATE), ("endDate", _DATE), ("timeZone", s()), ("polygon", ref("ZonePolygon")), ("bounds", ref("ZoneBounds")),
                                    ("amount", ref("Money")), ("progress", ref("BonusProgressNumbers")), ("earned", b()), ("earnedAt", ref("Timestamp")),
                                    ("isNew", b("He has not opened it yet (POST /driver/bonuses/opened)."))]),
                       ["bonusId", "names", "measure", "state", "startDate", "endDate", "timeZone", "polygon", "bounds", "amount", "progress", "earned", "isNew"],
                       _V + "a campaign as the driver sees it (no other driver's numbers). " + _BC["apps"]["driver"])
S["DriverBonusList"] = obj({"items": arr(ref("DriverBonus"))}, ["items"], _V + _BC["endpoints"]["driverList"])
S["DriverBonusOpened"] = obj({"bonusIds": arr(ref("Id"), minItems=1, maxItems=50, uniqueItems=True)}, ["bonusIds"], _V + _BC["endpoints"]["driverOpened"], addl=False)
PARAMS["BonusId"] = path_id("bonusId")
_BID = [pref("BonusId")]
op("get", "/admin/bonuses", "adminListBonusCampaigns", "Bonus campaigns", ["admin"], "Admin · People",
   params=[pref("ListZoneId"), q("state", ref("BonusState")), pref("Cursor"), pref("Limit")], ok=(200, "BonusCampaignPage"),
   permission="drivers.read", desc=_V + _BC["endpoints"]["adminList"])
op("post", "/admin/bonuses", "adminCreateBonusCampaign", "Create a bonus campaign", ["admin"], "Admin · People",
   body="BonusCampaignCreate", ok=(201, "BonusCampaign"), mutation=True, permission="drivers.bonuses", desc=_V + _BC["endpoints"]["adminCreate"])
op("get", "/admin/bonuses/{bonusId}", "adminGetBonusCampaign", "One bonus campaign", ["admin"], "Admin · People",
   params=_BID, ok=(200, "BonusCampaign"), permission="drivers.read", desc=_V + _BC["endpoints"]["adminRead"])
op("put", "/admin/bonuses/{bonusId}", "adminUpdateBonusCampaign", "Edit a bonus campaign (names, later end date)", ["admin"], "Admin · People",
   params=_BID, body="BonusCampaignUpdate", ok=(200, "BonusCampaign"), mutation=True, permission="drivers.bonuses", desc=_V + _BC["endpoints"]["adminUpdate"])
for _a, _sum in (("pause", "Pause a bonus campaign"), ("resume", "Resume a bonus campaign"), ("end", "End a bonus campaign")):
    op("post", "/admin/bonuses/{bonusId}/" + _a, "admin" + _a.capitalize() + "BonusCampaign", _sum, ["admin"], "Admin · People",
       params=_BID, body="BonusCampaignCommand", ok=(200, "BonusCampaign"), mutation=True, permission="drivers.bonuses", desc=_V + _BC["endpoints"]["adminPause"])
op("get", "/admin/bonuses/{bonusId}/drivers", "adminListBonusProgress", "Drivers' progress in a bonus campaign", ["admin"], "Admin · People",
   params=_BID + [pref("Cursor"), pref("Limit")], ok=(200, "BonusProgressPage"), permission="drivers.read", desc=_V + _BC["endpoints"]["adminDrivers"])
op("get", "/driver/bonuses", "listDriverBonuses", "My bonus campaigns and progress", ["driver"], "Driver · Money",
   ok=(200, "DriverBonusList"), desc=_V + _BC["endpoints"]["driverList"])
op("post", "/driver/bonuses/opened", "driverBonusesOpened", "I opened these campaigns", ["driver"], "Driver · Money",
   body="DriverBonusOpened", ok=(204, None), mutation=True, desc=_V + _BC["endpoints"]["driverOpened"])
# Money: the setting, the driver's earnings, the payout summary and the KPI day.
S["CountryRules"]["properties"]["bonusCampaignMax"] = {"allOf": [ref("Money")], "description": _V + C["configDefaults"]["bonusCampaignMax"]["note"]
    + " Defaults SE 2 000,00 kr (200000 SEK), FR 200,00 € (20000 EUR), TN 200.000 DT (200000 TND). Optional: absent → configDefaults.bonusCampaignMax."}
S["EarningsPeriod"]["properties"]["bonus"] = {"allOf": [ref("Money")], "description": _V + _BC["money"]["earnings"]}
S["EarningsPeriod"]["properties"]["net"] = {"allOf": [ref("Money")], "description": _V + "net includes bonus (every bonus entry of the period)."}
S["PayoutSummary"]["description"] = S["PayoutSummary"]["description"] + " " + C["priceDisplay"]["payoutSummary"]["campaignBonus"]
for _k in ("driverBonus", "moveraEarnings"):
    _p = S["KpiDay"]["properties"][_k]
    _p["description"] = (_p.get("description", "") + " " + C["moneyBase"]["bonusOutsideCommission"]["campaign"]).strip()
