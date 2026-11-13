# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.84 (S5 J7 debt model, owner Sitting 3
# 2026-11-12 Q-M1, Q-M2, Q-M4, Q-S5-1..5; 2026-11-13 14:22 / 14:32; contract.json#debtModel): an unpaid fee is a negative wallet
# balance read at payment; max rider debt blocks pay-in-car bookings; the driver owes-limit (OFF by default) + admin owing list
# and "Driver paid Movera".
_DM = C["debtModel"]
_DO = _DM["driverOwes"]

# Rider wallet may be below 0; two new entry kinds.
S["Wallet"]["properties"]["balance"]["description"] += " v0.18.84 (debtModel.riderWallet): may be below 0 — an unpaid fee is a negative balance (the debt)."
S["Wallet"]["properties"]["balances"]["description"] += " v0.18.84: a balance may be below 0 (a debt in that currency)."
_k = S["WalletEntry"]["properties"]["kind"]
assert "fee" not in _k["enum"] and "debt_paid" not in _k["enum"], "WalletEntry kinds changed before v0.18.84"
_k["enum"] = list(_k["enum"]) + ["fee", "debt_paid"]
_k["description"] = ("v0.18.84 (debtModel): fee = an unpaid cancel / no-show fee (negative, tripId = the trip that owes it); debt_paid = the debt "
                     "paid with a trip (positive, tripId = the paying trip). An admin correction stays adjustment.")
S["Rider"]["properties"]["outstanding"]["description"] += " v0.18.84 (debtModel.riderWallet): derived from the wallet: −min(0, balance) of the oldest owed currency."
S["Rider"]["properties"]["outstandingByCurrency"]["description"] += " v0.18.84: derived from the wallet balances below 0."

# Read at payment: quotes carry no debt; info field only.
assert "walletDebt" not in S["Quote"]["properties"], "Quote.walletDebt before v0.18.84"
S["Quote"]["properties"]["walletDebt"] = {"allOf": [ref("Money")], "description": "v0.18.84 (owner Q-M2 / Q-S5-5): " + _DM["quoteInfo"]}
PATHS["/quotes"]["post"]["description"] += " v0.18.84 (debtModel.readAtPayment, owner Q-M2): a quote no longer carries the outstanding_fee line; Quote.walletDebt shows the debt as information. " + _DM["readAtPayment"]
S["TripProjection"]["properties"]["debtCollected"]["description"] += " v0.18.84 (debtModel.readAtPayment): read from the wallet when the trip is paid, never copied in at booking. " + _DM["changeover"]
S["CreateTripRequest"]["properties"]["walletFirst"]["description"] += " v0.18.84 (owner Q-M1): " + _DM["walletSwitch"] + " walletApplied = max(0, min(balance, fare)): a negative balance pays nothing (supervisor M2)."

# Max rider debt per country: only pay-in-car bookings are refused.
_cr = S["CountryRules"]["properties"]
assert "maxRiderDebt" not in _cr and "driverOwesLimit" not in _cr, "CountryRules debt settings before v0.18.84"
_cr["maxRiderDebt"] = {"allOf": [ref("Money")], "description": "v0.18.84 (owner Q-M1, Q-S5-4, Q-S5-5): " + _DM["maxRiderDebt"] + " DB floor: " + _DM["dbFloor"]["note"]}
_op = PATHS["/trips"]["post"]
_op["responses"]["409"]["description"] += (" v0.18.84 (owner Q-S5-4 'Block only cash trip'): paymentMethod cash while the rider's debt in the trip's "
                                           "currency is at or above CountryRules.maxRiderDebt → conflict, reason rider_debt_above_max (contract.json#debtModel.maxRiderDebt).")

# Driver owes-limit: setting, go-online refusal, Home line.
S["DriverOwesLimit"] = obj({"enabled": dflt(b("Off by default in every country (owner Q-S5-1): nobody is blocked until the owner switches it on."), False),
                            "max": {"oneOf": [ref("Money"), {"type": "null"}], "description": "Admin-changeable at any time. The country's currency; required (> 0) when enabled (else 400 owes_limit_needs_amount). TN default 150000 TND (150 DT) stored, SE / FR null."}},
                           ["enabled"], "v0.18.84 (owner Q-S5-1 'Both', 2026-11-13 14:22 / 14:32 / 14:54): at or over it the driver gets no cash trips (never refused online). " + _DO["limit"] + " " + _DO["cashOffers"])
_cr["driverOwesLimit"] = ref("DriverOwesLimit")
_op = PATHS["/admin/trips/{tripId}/assign"]["post"]
assert _op["responses"]["409"] == rref("Conflict"), "assign 409 changed before v0.18.84"
_op["responses"]["409"] = err("version_mismatch / invalid_transition (with projection) or conflict. v0.18.84 (owner Q-S5-1 + 2026-11-13 14:54): "
                              "a cash (pay-in-car) trip to a driver at or over his country's owes-limit → conflict, reason driver_owes_movera "
                              "(contract.json#debtModel.driverOwes.cashOffers).", "ConflictError")
_rp = S["DriverReminder"]["properties"]
assert "owes_movera_over_limit" in _rp["kind"]["enum"] and "owed" not in _rp, "DriverReminder before v0.18.84"
_rp["owed"] = {"allOf": [ref("Money")], "description": "v0.18.84: owes_movera_over_limit lines (due_soon warning: no cash trips until he pays): what he owes Movera now."}
_rp["limit"] = {"allOf": [ref("Money")], "description": "v0.18.84: owes_movera_over_limit lines: his country's owes-limit."}

# Admin: who owes Movera, and "Driver paid Movera".
S["OwingDriver"] = obj({"driverId": ref("Id"), "driverName": s(), "zoneId": ref("Id"), "country": ref("CountryCode"),
                        "owed": {"allOf": [ref("Money")], "description": _DO["owed"]},
                        "limit": {"oneOf": [ref("Money"), {"type": "null"}], "description": "The country's owes-limit; null = off."},
                        "overLimit": b("owed is at or above limit: he gets no cash trips (false while off)."),
                        "lastPaidMoveraAt": ref("Timestamp")},
                       ["driverId", "owed", "limit", "overLimit"], "v0.18.84 (owner Q-S5-1a): one driver who owes Movera, in one currency.")
S["OwingDriverList"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("OwingDriver")), "total": i("All drivers who owe Movera in the filter.", minimum=0)}}],
                        "description": "Page<OwingDriver>, largest owed first."}
op("get", "/admin/drivers-owing", "adminListOwingDrivers", "Drivers who owe Movera", ["admin"], "Admin · Lists",
   params=[pref("Cursor"), pref("Limit"), pref("ListZoneId"), pref("ListZoneIds"), pref("ListCountry")], ok=(200, "OwingDriverList"),
   permission="finance.read", read_only=True, desc="v0.18.84 (owner Q-S5-1a 'Both'): " + _DO["adminList"])
S["PaidMoveraCommand"] = obj({"expectedOwed": {"allOf": [ref("Money")], "description": "The owed the admin saw; stale → 409 owed_changed."},
                              "amount": {"allOf": [ref("Money")], "description": "> 0, same currency, at most the owed now (else 400 paid_above_owed)."},
                              "reason": s("1..300 characters.", minLength=1, maxLength=_DO["reasonMax"])},
                             ["expectedOwed", "amount", "reason"], "v0.18.84 (owner Q-S5-1a 'Driver paid Movera').", addl=False)
_pm = op("post", "/admin/drivers/{driverId}/paid-movera", "adminDriverPaidMovera", "Driver paid Movera", ["admin"], "Admin · People",
         params=[pref("DriverId")], body="PaidMoveraCommand", ok=(200, "OwingDriver"), mutation=True, permission="finance.edit",
         desc="v0.18.84 (owner Q-S5-1a 'Both'): " + _DO["paidMovera"])
_pm["responses"]["409"] = err("v0.18.84: expectedOwed is stale → conflict, reason owed_changed with the fresh OwingDriver (nothing written; a second click is refused).", "ConflictError")

# Admin corrections on rider fees (no more fee_on_running_trip).
PATHS["/admin/riders/{riderId}/fees/{tripId}/mark-paid"]["post"]["description"] += " v0.18.84 (debtModel.adminCorrections): " + _DM["adminCorrections"]
