# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.153 (P29 driver income year file,
# EU DAC7; owner 2026-11-21 "Don't only save ! Execute ! ..." + "Also another one ( yearly but with monthly details ) ...",
# Rules LAUNCH-RULE.md P29): GET /admin/finance/driver-income (+ .csv) and GET /driver/income-statement
# (contract.json#driverIncomeYear). Additive.
_DI = C["driverIncomeYear"]
_M = _DI["money"]
_V153 = "v0.18.153 "
for _p in ("/admin/finance/driver-income", "/admin/finance/driver-income.csv", "/driver/income-statement"):
    assert _p not in PATHS, _p + " exists before v0.18.153"
assert "DriverIncomeRow" not in S, "DriverIncomeRow exists before v0.18.153"
_FIELDS = ["grossFares", "tips", "bonuses", "adjustments", "pickupPay", "feeShare", "moveraCommission", "moveraFees", "netEarnings", "cashCollectedByDriver", "paidOutByMovera"]
S["DriverIncomeTotals"] = obj(dict([("rides", i(_V153 + _M["rides"], minimum=0))] + [(f, money(_V153 + _M[f])) for f in _FIELDS]),
                              ["rides"] + _FIELDS, _V153 + _M["note"])
_T = lambda extra, req, desc: {"allOf": [ref("DriverIncomeTotals"), obj(extra, req)], "description": _V153 + desc}
S["DriverIncomeTripLine"] = _T({"localTime": s("Zone-local time 'YYYY-MM-DDTHH:MM' the line's money was credited (a payout: paid).", pattern="^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}$"),
                                "lineKind": s(enum=["trip", "credit", "payout"]),
                                "tripId": {"type": ["string", "null"], "description": "The trip; null for an entry with no trip (a bonus campaign)."},
                                "zoneId": {"type": ["string", "null"]},
                                "paymentMethod": {"type": ["string", "null"], "description": "The trip's payment method (cash = pay in the car); null with no trip."}},
                               ["localTime", "lineKind", "tripId", "zoneId", "paymentMethod"], "One trip line (detail trips): " + _DI["addUp"])
S["DriverIncomeDay"] = _T({"day": s(pattern="^\\d{4}-\\d{2}-\\d{2}$"), "trips": arr(ref("DriverIncomeTripLine"), description="detail trips only.")}, ["day"], "One zone-local day.")
S["DriverIncomeMonth"] = _T({"month": s(pattern="^\\d{4}-\\d{2}$"), "days": arr(ref("DriverIncomeDay"), description="detail day and trips only.")}, ["month"], "One month.")
S["DriverIncomeQuarter"] = _T({"quarter": i(minimum=1, maximum=4)}, ["quarter"], "One quarter (Q1 = January-March).")
S["DriverIncomeRow"] = _T({
    "kind": s(enum=["company", "driver"]), "payeeId": s("The fleetId (company) or the driverId (driver)."), "name": s(),
    "orgNumber": {"type": ["string", "null"]}, "address": {"type": ["string", "null"]}, "country": {"type": ["string", "null"], "pattern": "^[A-Z]{2}$"},
    "currency": ref("CurrencyCode"),
    "bank": {"oneOf": [obj({"holder": s(), "last4": s(pattern="^[0-9A-Z]{1,4}$")}, ["holder", "last4"]), {"type": "null"}], "description": "Holder and last 4 only, never the full account; null when not stored as data."},
    "driverIds": arr(ref("Id")), "ownPartOnly": b(_DI["driver"]["fleetDriver"]), "partial": b(_DI["partial"]),
    "quarters": arr(ref("DriverIncomeQuarter")), "months": arr(ref("DriverIncomeMonth"), description="detail month, day and trips."),
}, ["kind", "payeeId", "name", "orgNumber", "address", "country", "currency", "bank", "driverIds", "quarters"], _DI["payee"] + " " + _DI["periods"])
S["DriverIncomePage"] = obj({"year": i(minimum=2020), "detail": s(enum=["quarter", "month", "day", "trips"]), "month": s(pattern="^\\d{4}-\\d{2}$"),
                             "items": arr(ref("DriverIncomeRow")), "nextCursor": {"type": ["string", "null"]}, "generatedAt": ref("Timestamp")},
                            ["year", "detail", "items", "nextCursor", "generatedAt"], _V153 + "Page of GET /admin/finance/driver-income.")
S["DriverIncomeStatement"] = obj({"year": i(minimum=2020), "detail": s(enum=["month", "day", "trips"]), "month": s(pattern="^\\d{4}-\\d{2}$"), "items": arr(ref("DriverIncomeRow"))},
                                 ["year", "detail", "items"], _V153 + _DI["driver"]["endpoint"])
_A = _DI["admin"]
_YEAR = {"name": "year", "in": "query", "required": True, "schema": i(minimum=2020)}
_INQ = [_YEAR, *ZF, q("detail", s(enum=["quarter", "month", "day", "trips"], default="quarter")), q("month", s(pattern="^\\d{4}-\\d{2}$")), q("payeeId", ref("Id"))]
op("get", "/admin/finance/driver-income", "adminDriverIncome", "Yearly income per driver or company (DAC7, for the accountant)", ["admin"], "Admin · Money",
   params=_INQ + [pref("Cursor"), {"name": "limit", "in": "query", "required": False, "schema": i(minimum=1, maximum=200, default=50)}],
   ok=(200, "DriverIncomePage"), permission="finance.read",
   desc=_V153 + "(contract.json#driverIncomeYear): " + " ".join(_A[k] for k in ("scope", "detail", "tooBig", "errors", "paging", "audit")))
op("get", "/admin/finance/driver-income.csv", "adminDriverIncomeCsv", "The same as a CSV file for the accountant", ["admin"], "Admin · Money",
   params=_INQ, permission="finance.read", content={"text/csv": {"schema": {"type": "string"}}}, ok_desc="CSV file",
   desc=_V153 + _A["csv"] + " " + _A["audit"])
op("get", "/driver/income-statement", "driverIncomeStatement", "The driver's own year statement", ["driver"], "Driver · Money",
   params=[_YEAR, q("detail", s(enum=["month", "day", "trips"], default="month")), q("month", s(pattern="^\\d{4}-\\d{2}$"))],
   ok=(200, "DriverIncomeStatement"), desc=_V153 + _DI["driver"]["endpoint"] + " " + _DI["driver"]["fleetDriver"])
