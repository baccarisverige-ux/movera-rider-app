"""Reference engine for contract.json: replays fixtures/scenarios.json, events.json, money.json, cancel_fees.json, pickup_pay.json, surge.json, payouts.json,
fares.json, dispatch.json and settings_flow.json (v0.8.0), and checks the pricing and dispatch sample documents agree with contract.json#configDefaults.
Each app's contract tests must give the same answers."""
import json, sys
c = json.load(open('contract.json'))
term = set(c['tripStatus']['terminal'])
def step(status, command, actor, kind):
    for t in c['transitions']:
        if t['command'] == command and t['actor'] == actor and status in t['from'] and t.get('when', kind) == kind:
            return t['to']
    return None
def may_rate(rater, status, ended_by):
    return any(r['rater'] == rater and r['status'] == status and r.get('command', ended_by) == ended_by
               for r in c['ratingAllowed']['rules'])
bad = 0
for s in json.load(open('fixtures/scenarios.json'))['scenarios']:
    st, ended_by = 'draft', None
    for cmd, actor, expect in s['steps']:
        nxt = step(st, cmd, actor, s['kind'])
        got = nxt if nxt else 'invalid_transition'
        if got != expect:
            bad += 1; print('SCENARIO', s['id'], cmd, actor, 'from', st, 'expected', expect, 'got', got)
        if nxt: st, ended_by = nxt, cmd
    for rater, expect in s.get('rating', {}).items():
        got = 'allowed' if st in term and may_rate(rater, st, ended_by) else 'invalid_transition'
        if got != expect:
            bad += 1; print('RATING', s['id'], rater, 'after', st, 'by', ended_by, 'expected', expect, 'got', got)
after = set(c['realtime']['afterTerminal'])
for case in json.load(open('fixtures/events.json'))['cases']:
    last, seen, terminal = 0, set(), False
    for e in case['events']:
        if e['sequence'] < 1 or not e['tripId']: got = 'invalid'
        elif e['eventId'] in seen or e['sequence'] <= last: got = 'duplicate'
        elif terminal and e['kind'] not in after: got = 'blocked_after_terminal'; last = e['sequence']; seen.add(e['eventId'])
        else:
            got = 'accepted_with_gap' if last and e['sequence'] > last + 1 else 'accepted'
            last = e['sequence']; seen.add(e['eventId'])
            if e.get('status') in term: terminal = True
        if got != e['expect']:
            bad += 1; print('EVENT', case['id'], e['eventId'], 'expected', e['expect'], 'got', got)
exp = c['currencies']
for m in json.load(open('fixtures/money.json'))['cases']:
    n = exp[m['money']['currency']]['exponent']; a = m['money']['amountMinor']
    major = ('-' if a < 0 else '') + f"{abs(a)//10**n}.{abs(a)%10**n:0{n}d}"
    if major != m['major']: bad += 1; print('MONEY', m, major)
for f in json.load(open('fixtures/cancel_fees.json'))['cases']:
    r = f['rule']; fare = f['fare']['amountMinor']
    free = f['minutesSinceAccept'] < r['freeMin'] if f['kind'] == 'live' else f['minutesBeforePickup'] >= r['freeMin']
    fee = 0 if free else (r['value'] if r['type'] == 'fixed' else (fare * r['value'] * 2 + 100) // 200)
    if not free and r['min']: fee = max(fee, r['min']['amountMinor'])
    if not free and r['max']: fee = min(fee, r['max']['amountMinor'])
    if fee != f['fee']['amountMinor']: bad += 1; print('FEE', f['id'], fee)
import math
def _half_up(x): return int(math.floor(x + 0.5))
def pickup_pay(rate, offers, kind, km, minutes):
    """contract.json#pickupPay: tiered ranges, minutes split by km share, capped at maxPerRide; 0 when off."""
    if kind == 'scheduled' or not offers.get(kind) or not rate['enabled'] or not rate['ranges']: return 0
    km, minutes, total, rs = max(0.0, km), max(0.0, minutes), 0, rate['ranges']
    for i, r in enumerate(rs):
        end = math.inf if r['toKm'] is None or i == len(rs) - 1 else r['toKm']
        inr = max(0.0, min(km, end) - r['fromKm'])
        share = inr / km if km > 0 else (1.0 if i == 0 else 0.0)
        if inr <= 0 and share <= 0: continue
        total += _half_up(inr * r['perKm']['amountMinor']) + _half_up(minutes * share * r['perMin']['amountMinor'])
    mx = rate['maxPerRide']
    return min(total, mx['amountMinor']) if mx is not None else total
for p in json.load(open('fixtures/pickup_pay.json'))['cases']:
    got = pickup_pay(p['rate'], p['offers'], p['offerKind'], p['pickupKm'], p['pickupMinutes'])
    if got != p['pay']['amountMinor']: bad += 1; print('PICKUP', p['id'], 'expected', p['pay']['amountMinor'], 'got', got)
from datetime import datetime, timezone
def _ts(t): return datetime.strptime(t, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
def _value_at(points, minute):
    if minute <= points[0]['atMin']: return points[0]['multiplier']
    for i in range(1, len(points)):
        a, b = points[i - 1], points[i]
        if minute <= b['atMin']:
            span = b['atMin'] - a['atMin']
            return b['multiplier'] if span <= 0 else a['multiplier'] + (b['multiplier'] - a['multiplier']) * (minute - a['atMin']) / span
    return points[-1]['multiplier']
def surge_at(s, at):
    """contract.json#surge: the curve's value at the start of the current step slot, rounded half-up to 0.1, within [1, cap]; None outside the schedule."""
    start, end, now = _ts(s['startAt']), _ts(s['endAt']), _ts(at)
    if now < start or now >= end: return None
    minute = int((now - start).total_seconds() // 60)
    slot = (minute // s['stepMinutes']) * s['stepMinutes']
    return min(s['cap'], max(1.0, math.floor(_value_at(s['points'], slot) * 10 + 0.5) / 10))
sj = json.load(open('fixtures/surge.json'))
for case in sj['cases']:
    got = surge_at(sj['schedule'], case['at'])
    if got != case['multiplier']: bad += 1; print('SURGE', case['at'], 'expected', case['multiplier'], 'got', got)
# ---- v0.7.1: overlapping planned surges (the higher counts) and smart surge (contract.json#smartSurge)
from datetime import datetime as _dt
_ts = lambda x: _dt.fromisoformat(x.replace('Z', '+00:00'))
ov = sj['scheduledOverlap']
for case in ov['cases']:
    got = max([w['multiplier'] for w in ov['windows'] if _ts(w['startsAt']) <= _ts(case['at']) < _ts(w['endsAt'])] or [1.0])
    if got != case['multiplier']: bad += 1; print('SURGE OVERLAP', case['at'], 'expected', case['multiplier'], 'got', got)
def hm(s): h, m = s.split(':'); return int(h) * 60 + int(m)
def profile_at(smart, weekday, minute):
    """First non-default profile from the top whose days and windows match (a window may wrap midnight; from == to is all day), else the default."""
    for p in smart['profiles']:
        if p['isDefault']: continue
        for w in p['windows']:
            f, t = hm(w['from']), hm(w['to'])
            y = (weekday + 6) % 7
            if (f == t and weekday in p['days']) or (f < t and weekday in p['days'] and f <= minute < t) or \
               (f > t and ((weekday in p['days'] and minute >= f) or (y in p['days'] and minute < t))): return p['id']
    return next((p['id'] for p in smart['profiles'] if p['isDefault']), None)
def in_hours(smart, minute):
    f, t = hm(smart['activeFrom']), hm(smart['activeTo'])
    return f == t or (f < t and f <= minute < t) or (f > t and (minute >= f or minute < t))
def target(profile, ratio, max_mult):
    m = 1.0
    for s in profile['steps']:
        if ratio >= s['ratio']: m = s['multiplier']
    return min(m, profile['cap'], max_mult)
def run(smart, profile, max_mult, checks):
    """checks: [{atMin, ratio}] in order. Returns the applied multiplier after each check."""
    cur, up_since, low_since, last = 1.0, None, None, None
    levels = sorted({min(s['multiplier'], profile['cap'], max_mult) for s in profile['steps']})
    out = []
    for c in checks:
        t, tg = c['atMin'], target(profile, c['ratio'], max_mult)
        cool = last is None or t - last >= smart['cooldownMin']
        low_since = (low_since if low_since is not None else t) if tg == 1.0 else None
        if tg > cur:
            up_since = up_since if up_since is not None else t
            if t - up_since >= smart['holdMin'] and cool: cur, last, up_since = tg, t, None
        else:
            up_since = None
            if tg < cur:
                if low_since is not None and t - low_since >= smart['stopAfterMin']: cur, last = 1.0, t
                elif cool:
                    lower = [l for l in levels if l < cur]
                    cur, last = max(max(lower) if lower else 1.0, tg), t
        out.append(cur)
    return out
ssj = json.load(open('fixtures/smart_surge.json')); _smart = json.load(open('fixtures/config/pricing_document.json'))['surge']['smart']
for case in ssj['cases']:
    prof = next(p for p in _smart['profiles'] if p['id'] == case['profileId'])
    got = run(_smart, prof, case['maxMultiplier'], case['checks'])
    if got != case['expect']: bad += 1; print('SMART SURGE', case['id'], 'expected', case['expect'], 'got', got)
for pk in ssj['profilePicks']:
    if profile_at(_smart, pk['weekday'], pk['minute']) != pk['expect']: bad += 1; print('SMART PROFILE', pk)
# v0.7.1: the sample app documents carry each seed category's sub-line (contract.json#categoryCatalog.seedLines)
for _f in ('fixtures/config/rider_app_config.json', 'fixtures/config/driver_app_config.json'):
    for _cat in json.load(open(_f)).get('catalog', {}).get('categories', []):
        if _cat['id'] in c['categoryCatalog']['seedLines'] and _cat.get('line') != c['categoryCatalog']['seedLines'][_cat['id']]: bad += 1; print('CATALOG LINE', _f, _cat['id'])
# ---- v0.5.1: fares (contract.json#pricing, CONTRACT.md §3.5)
from fractions import Fraction as Fr
def _hu(x): return math.floor(x + Fr(1, 2))
def _merge(a, b):
    if isinstance(a, dict) and isinstance(b, dict): return {**a, **{k: _merge(a[k], v) if k in a else v for k, v in b.items()}}
    return b
def seats(cat, inp, amt, cid):
    """v0.7.1: ONE seat fee, only on child_seat (owner 2026-10-27): a child_seat trip always includes one seat, its fee once.
    The rider never sends a number; babySeats / childSeats above 0 on another category are refused."""
    if cid != 'child_seat' and any(inp.get(k, 0) for k in ('babySeats', 'childSeats')): raise ValueError('seat_not_offered')
    return amt(cat['childSeatFee']) if cid == 'child_seat' and 'childSeatFee' in cat else Fr(0)
def price(doc, inp):
    """Every line exact until rounded half-up to a minor unit; the total rounded once to priceStep; outstanding_fee after that."""
    cat, amt, lines = doc['categories'][inp['categoryId']], (lambda m: Fr(m['amountMinor'])), []
    add = lambda code, v, keep=False: lines.append((code, v)) if (v != 0 or keep) else None
    ee = inp.get('endEarly')
    km, mins = Fr(str(ee['kmDriven'] if ee else inp['km'])), Fr(str(ee['minutesOnBoard'] if ee else inp['minutes']))
    route = None if ee else next((r for r in doc['fixedRoutes'] if r['id'] == inp.get('fixedRouteId') and r['categoryId'] == inp['categoryId']), None)
    if route: ride = amt(route['price']); add('fixed_route', ride, True)
    else:
        parts = [('base', amt(cat['base'])), ('distance', amt(cat['perKm']) * km), ('time', amt(cat['perMin']) * mins)]
        for code, v in parts: add(code, v, True)
        ride = sum(v for _, v in parts)
        mult = min(max(Fr(str(inp.get('surgeMultiplier', 1))), Fr(1)), Fr(str(c['pricing']['maxMultiplier'])))   # v0.7.1: the slider's top; no zone maximum
        if mult > 1: add('surge', ride * (mult - 1)); ride *= mult
        if ride < amt(cat['minimum']): add('minimum_adjust', amt(cat['minimum']) - ride); ride = amt(cat['minimum'])
        if cat['maximum'] is not None and ride > amt(cat['maximum']): add('maximum_adjust', amt(cat['maximum']) - ride); ride = amt(cat['maximum'])
    pct = Fr(str(cat['appFeePct'])) / 100
    fee = cat['riderPickupFee']['reservation' if inp['kind'] == 'scheduled' else 'live']
    fee = amt(fee) if fee else Fr(0)
    extras = waiting = Fr(0); wait_lines = 0
    if ee:
        cap = (amt(ee['bookedFare']) - fee) / (1 + pct)
        if ride > cap: add('maximum_adjust', cap - ride); ride = cap
    else:
        stops = inp.get('stopWaitSeconds', [])   # v0.7.1: arrived-at-stop to leaving-stop, no free minutes
        w = Fr(inp.get('waitingChargedSeconds', 0)) / 60 * amt(cat['waiting']['perMin'])
        sw = Fr(sum(max(0, x) for x in stops)) / 60 * amt(cat['stopWaitPerMin'])
        f = doc['fees']
        for code, v in [('waiting', w), ('stops', len(stops) * amt(cat['extraStopFee'])), ('stop_waiting', sw),
                        ('extras', seats(cat, inp, amt, inp['categoryId'])),
                        ('airport', (amt(f['airportPickup']) if inp.get('pickupInAirportZone') else 0) + (amt(f['airportDropoff']) if inp.get('dropoffInAirportZone') else 0)),
                        ('reservation_fee', amt(f['reservationFee']) if inp['kind'] == 'scheduled' else 0)]:
            if v > 0: add(code, v); extras += v
        waiting, wait_lines = w + sw, _hu(w) + _hu(sw)
    before = ride + extras
    add('app_fee', before * pct); add('pickup_fee', fee)
    step = amt(doc['priceStep'])
    total = _hu((before + before * pct + fee) / step) * step
    out = [{'code': k, 'amount': int(_hu(v))} for k, v in lines]
    if total != sum(l['amount'] for l in out): out.append({'code': 'rounding', 'amount': int(total - sum(l['amount'] for l in out))})
    driver = int(min(total, _hu((before - waiting) * (1 - Fr(str(cat['commissionPct'])) / 100)) + wait_lines))
    owed = inp.get('outstandingFee')
    if owed: out.append({'code': 'outstanding_fee', 'amount': owed['amountMinor']}); total += owed['amountMinor']
    return int(total), out, driver
riders = set(c['fareLines']['rider'])
fj = json.load(open('fixtures/fares.json')); pdoc = json.load(open(fj['document']))
for f in fj['cases']:
    e = f['expect']
    try: total, lines, driver = price(_merge(pdoc, f.get('overrides', {})), f['input'])
    except ValueError as err:
        if e.get('error') != str(err): bad += 1; print('FARE', f['id'], 'expected', e, 'got error', err)
        continue
    if 'error' in e: bad += 1; print('FARE', f['id'], 'expected error', e['error'], 'got', total); continue
    want = [{'code': l['code'], 'amount': l['amount']['amountMinor']} for l in e['fareLines']]
    if (total, lines, driver, total - driver) != (e['total']['amountMinor'], want, e['driverEarnings']['amountMinor'], e['moveraShare']['amountMinor']) \
            or not all(l['code'] in riders for l in want) or sum(l['amount'] for l in want) != total:
        bad += 1; print('FARE', f['id'], 'expected', e['total']['amountMinor'], want, e['driverEarnings']['amountMinor'], 'got', total, lines, driver)
se = c['configDefaults']['pricing']['countries']['SE']
for cid, row in se['categories'].items():
    x = pdoc['categories'][cid]
    got = {'base': x['base'], 'perKm': x['perKm'], 'perMin': x['perMin'], 'minimum': x['minimum'], 'maximum': x['maximum'], 'extraStopFee': x['extraStopFee'],
           'stopWaitPerMin': x['stopWaitPerMin'], 'childSeatFee': x.get('childSeatFee'), 'waitPerMin': x['waiting']['perMin'], 'noShowFee': x['waiting']['noShowFee']}
    got = {k: (v['amountMinor'] if v else None) for k, v in got.items() if v is not None or k != 'childSeatFee'}
    got.update(appFeePct=x['appFeePct'], commissionPct=x['commissionPct'], freeWaitMin=x['waiting']['freeWaitMin'])
    if got != dict(row) or x['waiting']['noShowAfterMin'] != x['waiting']['freeWaitMin']: bad += 1; print('PRICING DEFAULTS', cid, got, row)
if (pdoc['priceStep']['amountMinor'], pdoc['surge']['maxMultiplier'], pdoc['surge']['smart']['enabled'], pdoc['fleetCommissionPct']) != \
        (se['priceStep'], se['surgeMaxMultiplier'], se['smartSurge'], se['fleetCommissionPct']): bad += 1; print('PRICING DEFAULTS zone')
# ---- v0.5.1: automatic dispatch (contract.json#dispatch, CONTRACT.md §3.6)
def _round1(x): return math.floor(x * 10 + 0.5) / 10
def search(doc, case):
    """One search from t = 0: the start mode, every offer, the rider-waiting steps that fired and the end."""
    K, ctl = c['dispatch'], case.get('control') or c['dispatch']['control']['default']
    busy = _round1(case['waitingRequests'] / max(1, case['freeDrivers']))
    hm = lambda s: int(s[:2]) * 60 + int(s[3:])
    def in_time(r):
        now, a, b = hm(case['localTime']), hm(r['from']), hm(r['to'])
        return a <= now < b if a < b else (now >= a or now < b)
    ch = doc['choose']
    timed = next((r for r in ch['times'] if r['on'] and doc[r['mode']]['on'] and in_time(r)), None)
    if ctl['paused']: mode = None
    elif ctl['mode']: mode = ctl['mode']
    elif timed: mode = timed['mode']
    elif ch['how'] == 'auto' and doc['radar']['on'] and doc['exclusive']['on']: mode = 'radar' if busy >= ch['radarAbove'] else 'exclusive'
    else: mode = ch['main'] if doc[ch['main']]['on'] else 'radar' if doc['radar']['on'] else 'exclusive' if doc['exclusive']['on'] else None
    sc, fb, fin = K['score'], K['fallbacks'], doc['finishing']
    weights = {f['id']: f['weight'] for f in doc['factors'] if f['on']}; wsum = sum(weights.values()) or 1
    steps = doc['radius']['steps']
    rows = []
    for d in case['drivers']:
        f = d.get('finishing')
        near = bool(f) and fin['exclusive'] and 'finishing' in weights and f['inMin'] <= fin['withinMin'] and f['dropKm'] <= fin['withinKm']
        km = f['dropKm'] if f else d['km']
        eta = max(1, _half_up(km / sc['pickupKmh'] * 60) + (f['inMin'] if f else 0))
        fav = bool(d.get('favourite')) and doc['favourite']['on'] and km <= doc['favourite']['maxKm']
        ratios = {'eta': 1 - eta / sc['etaFullMin'], 'rating': (d.get('rating', fb['rating']) - sc['ratingFloor']) / sc['ratingSpan'],
                  'acceptance': d.get('acceptancePct', fb['acceptancePct']) / 100, 'cancel': 1 - d.get('cancelPct', fb['cancelPct']) / sc['cancelZeroPct'],
                  'idle': d.get('idleMin', 0) / sc['idleFullMin'], 'finishing': 1 if near else None, 'favourite': 1 if fav else None}
        score = sum(_half_up(w / wsum * 100 * max(0.0, min(1.0, ratios[k]))) for k, w in weights.items() if w and ratios[k] is not None)
        out = (f and not near) or case['categoryId'] not in d.get('categoryIds', [case['categoryId']]) or km > steps[-1]
        rows.append({'id': d['driverId'], 'km': km, 'score': score, 'fav': fav and weights.get('favourite'), 'near': near, 'riding': bool(f), 'from': d.get('freeFromSec', 0), 'out': out})
    rows.sort(key=lambda r: (-r['score'], r['km'], r['id']))
    def in_range(m, t, km): return [r for r in rows if not r['out'] and r['from'] <= t and r['km'] <= km and
                                    (not r['riding'] or (m == 'exclusive' and fin['exclusive'] and doc['exclusiveWhileDriving']['on']))]
    waits = sorted([dict(w, at=w['afterMin'] * 60) for w in doc['waiting'] if w['on'] and w['kind'] not in K['skippedWaitingKinds']], key=lambda w: w['afterMin'])
    S = {'end': min([doc['radius']['maxWaitMin'] * 60] + [w['at'] for w in waits if w['kind'] == 'busy']), 'outcome': None, 'fired': [], 'done': set()}
    answers = case.get('riderAnswers', [])
    def run_until(upto):
        while S['outcome'] is None:
            fired = {f['id'] for f in S['fired']}
            items = [(w['at'], 0, w) for w in waits if w['id'] not in S['done']] + [(a['atSec'], 1, a) for a in answers if a['stepId'] in fired and id(a) not in S['done']]
            if not items: return
            at, kind, it = min(items, key=lambda x: (x[0], x[1]))
            if at > upto or at > S['end']: return
            if kind == 0:
                S['done'].add(it['id']); S['fired'].append({'id': it['id'], 'kind': it['kind'], 'atSec': at})
                if it['kind'] == 'busy': S['end'] = at
            else:
                S['done'].add(id(it))
                if it['answer'] == 'stop': S['outcome'], S['end'] = ('cancelled_by_rider', at, None), at
                else:
                    S['end'] += next(w for w in waits if w['id'] == it['stepId'])['extraMin'] * 60
                    for w in waits:
                        if w['kind'] == 'busy' and w['id'] not in S['done']: w['at'] = max(w['at'], S['end'])
    offers, nth = [], {}
    def offer(kind, t, km, ids, reason=None):
        exp = min(t + doc[kind]['seconds'], S['end'])
        offers.append({'atSec': t, 'kind': kind, 'radiusKm': km, 'driverIds': ids, 'expiresAtSec': exp, **({'reasonCode': reason} if reason else {})})
        won, declined = None, {}
        for i in ids:
            nth[i] = nth.get(i, 0) + 1
            for a in case.get('offerAnswers', []):
                at = t + a['afterSec']
                if a['driverId'] == i and a.get('nth', 1) == nth[i] and at < exp:
                    if a['answer'] == 'accept' and (won is None or at < won[0]): won = (at, i)
                    if a['answer'] == 'decline': declined[i] = at
        if won:
            run_until(won[0])
            if S['outcome'] is None: S['outcome'] = ('accepted', won[0], won[1])
            return won[0]
        nxt = max(declined.values()) if len(declined) == len(ids) else exp
        run_until(nxt)
        return nxt
    t, step, cur, tried, asked, switched, repeat = 0, 0, mode, 0, set(), set(), False
    while mode:
        run_until(t)
        if S['outcome'] or t >= S['end']: break
        if repeat:  # steps used up (owner decision 22): Exclusive to a driver not yet asked, else a Radar round, else wait and look again
            km = steps[-1]; ex = in_range('exclusive', t, km); nxt = next((r for r in ex if r['id'] not in asked), None)
            shown = in_range('radar', t, km)[:doc['radar']['drivers']]
            if doc['exclusive']['on'] and nxt:
                asked.add(nxt['id'])
                t = offer('exclusive', t, km, [nxt['id']], 'favourite' if nxt['fav'] else 'finishing-nearby' if nxt['near'] else 'best-match' if nxt is ex[0] else 'nearby')
            elif doc['radar']['on'] and shown: t = offer('radar', t, km, [r['id'] for r in shown])
            else: t += doc['radar']['seconds'] if doc['radar']['on'] else doc['exclusive']['seconds']
            continue
        km = steps[step]; ring = in_range(cur, t, km); widest = step == len(steps) - 1
        if cur == 'radar':
            shown = ring[:doc['radar']['drivers']]
            if shown: t = offer('radar', t, km, [r['id'] for r in shown])
            then = doc['radar']['then']
            if then in ('widen', 'widen_then_exclusive') and not widest: step += 1
            elif then in ('exclusive', 'widen_then_exclusive') and doc['exclusive']['on'] and 'exclusive' not in switched: switched.add('exclusive'); cur, tried = 'exclusive', 0
            elif not widest: step += 1
            else: repeat = True
        else:
            nxt = next((r for r in ring if r['id'] not in asked), None)
            if nxt and tried < doc['exclusive']['drivers']:
                asked.add(nxt['id']); tried += 1
                t = offer('exclusive', t, km, [nxt['id']], 'favourite' if nxt['fav'] else 'finishing-nearby' if nxt['near'] else 'best-match' if nxt is ring[0] else 'nearby')
                continue
            then = doc['exclusive']['then']
            if then in ('widen', 'widen_then_radar') and not widest: step, tried = step + 1, 0
            elif then in ('radar', 'widen_then_radar') and doc['radar']['on'] and 'radar' not in switched: switched.add('radar'); cur = 'radar'
            elif not widest: step, tried = step + 1, 0
            else: repeat = True
    run_until(S['end'])
    outcome, at, who = S['outcome'] or ('expired', S['end'], None)
    return {'busy': busy, 'mode': mode, 'offers': offers, 'searchSteps': S['fired'], 'end': {'atSec': at, 'outcome': outcome, **({'driverId': who} if who else {})}}
dj = json.load(open('fixtures/dispatch.json')); ddoc = json.load(open(dj['document']))
for case in dj['cases']:
    got = search(ddoc, case)
    if got != case['expect']: bad += 1; print('DISPATCH', case['id'], 'expected', case['expect'], 'got', got)
dz = c['configDefaults']['dispatch']['zone']
if any(ddoc[k] != v for k, v in dz.items()): bad += 1; print('DISPATCH DEFAULTS differ from fixtures/config/dispatch_document.json')
# v0.6.0: seat fees only on child_seat (owner 2026-10-27); child_seat in the seed with its label.
if any('babySeatFee' in x or ('childSeatFee' in x) != (cid == 'child_seat') for cid, x in pdoc['categories'].items()): bad += 1; print('SEAT FEE not only on child_seat (v0.7.1: one seat fee, no baby seat fee)')
if 'stopFreeWaitMin' in pdoc: bad += 1; print('stopFreeWaitMin is gone in v0.7.1 (no free minutes at a stop)')
if 'child_seat' not in c['categories']['seed'] or set(c['categories']['labels']) != set(c['categories']['seed']): bad += 1; print('CATEGORY seed / labels')
if not (1 <= pdoc['surge']['maxMultiplier'] <= c['pricing']['maxMultiplier'] == c['surge']['capMax']): bad += 1; print('SURGE maximum')
# configDocs.mustMatch against the sample app documents (aligned with the pricing document in v0.6.0).
rcfg = json.load(open('fixtures/config/rider_app_config.json')); dcfg = json.load(open('fixtures/config/driver_app_config.json'))
WK = ('freeWaitMin', 'perMin', 'noShowAfterMin', 'noShowFee')
head = pdoc['categories']['economy' if 'economy' in pdoc['categories'] else next(iter(pdoc['categories']))]
for name, cfg in (('rider', rcfg), ('driver', dcfg)):
    if any(cfg['waiting'][k] != head['waiting'][k] for k in WK): bad += 1; print('MUSTMATCH', name, 'top-level waiting')
    for cid, w in cfg['waiting']['byCategory'].items():
        if any(w[k] != pdoc['categories'][cid]['waiting'][k] for k in WK): bad += 1; print('MUSTMATCH', name, 'waiting', cid)
for cid, fee in rcfg['pickupFee']['byCategory'].items():
    if fee != pdoc['categories'][cid]['riderPickupFee']: bad += 1; print('MUSTMATCH rider pickupFee', cid)
for cid, rate in dcfg['pickupPay']['byCategory'].items():
    if rate['riderFee'] != pdoc['categories'][cid]['riderPickupFee']: bad += 1; print('MUSTMATCH driver riderFee', cid)
# v0.8.0 settings flow: country standard, server-stamped versions, country rules, auto-offline, booking snapshot.
sf = json.load(open('fixtures/settings_flow.json'))
def served(own, standard, zone):
    if zone['zoneId'] in own: return {'usesStandard': False, 'version': own[zone['zoneId']]}
    if zone['country'] in standard: return {'usesStandard': True, 'version': standard[zone['country']]}
    return {'usesStandard': False, 'version': None}
for case in sf['standard']:
    got = served(case['own'], case['standard'], case['zone'])
    if got != case['expect']: bad += 1; print('STANDARD', case['id'], 'expected', case['expect'], 'got', got)
for case in sf['versions']:
    own, std, seen = None, None, 0
    for st in case['steps']:
        if st['publish'] == 'standard': std = (std or 0) + 1
        else: own = max(own or 0, seen, std or 0) + 1
        seen = own if own is not None else std   # what the zone's apps see (adminVersion is ignored)
        if seen != st['expect']: bad += 1; print('VERSION', case['id'], st, 'got', seen)
for case in sf['countryRules']:
    got = dict(case['document']) if case['rules'] is None else {k: case['rules'][k] for k in ('tips', 'raiseSteps', 'driverBonus')}
    if got != case['expect']: bad += 1; print('COUNTRY RULES', case['id'], 'got', got)
def auto_offline(limit, offers):
    run = 0
    for idx, o in enumerate(offers):
        if o == 'on': run = 0; continue
        kind, outcome = o[0], o[1]
        if outcome == 'a': run = 0; continue          # any accepted offer starts the run again
        if kind != 'x': continue                      # radar, assigned, scheduled and on-trip ('t') misses never count
        run += 1
        if run >= limit: return idx
    return None
if c['autoOffline']['counts'] != ['exclusive'] or c['autoOffline']['resets'][0] != 'any offer accepted' or c['configDefaults']['missedExclusiveBeforeOffline'] != 10: bad += 1; print('AUTO OFFLINE rule')
for case in sf['autoOffline']:
    got = auto_offline(case['limit'], case['offers'])
    if got != case['expectOfflineAt']: bad += 1; print('AUTO OFFLINE', case['id'], 'expected', case['expectOfflineAt'], 'got', got)
for case in sf['snapshot']:
    kept = case['atBooking']   # the trip's rules are the ones of booking time; publishedLater must not matter
    fee = kept['cancelRule']['value'] if kept['cancelRule']['type'] == 'fixed' else None
    got = {'cancelFee': fee, 'cancelDriverPart': fee * kept['cancelDriverSharePct'] // 100,
           'noShowFee': kept['noShowFee'], 'noShowDriverPart': kept['noShowFee'] * kept['noShowDriverSharePct'] // 100}
    if got != case['expect']: bad += 1; print('SNAPSHOT', case['id'], 'got', got)
if not (c['configDefaults']['cancelDriverSharePct'] == c['cancelFees']['driverSharePctDefault'] == 100): bad += 1; print('CANCEL SHARE default')
for case in sf['useStandard']:
    std = max(case['standard'], case['own']) + 1
    got = {'standard': std, 'servedVersion': std, 'usesStandard': True}
    if got != case['expect']: bad += 1; print('USE STANDARD', case['id'], 'got', got)
# v0.7.2: the driver map's colour levels (contract.json#driverSurgeMap.levels)
def surge_level(m):
    return None if m <= 1.0 else 'low' if m < 1.5 else 'medium' if m <= 2.5 else 'high'
for case in json.load(open('fixtures/surge_levels.json'))['cases']:
    if surge_level(case['multiplier']) != case['level']: bad += 1; print('SURGE LEVEL', case)
# v0.9.0: payout lines (fixtures/payouts.json, contract.json#payouts).
def payout(entries):
    lines = {code: 0 for code in c['payouts']['lines']}
    trips = 0
    for e in entries:
        if e.get('inPayout'): continue
        k, a = e['kind'], e['amountMinor']
        if k == 'trip':
            trips += 1; lines['waiting'] += e['waitingMinor']; lines['trips'] += a - e['waitingMinor']; lines['cash_collected'] -= e['cashMinor']
        elif k == 'adjustment': lines['trips'] += a
        elif k == 'pickup_pay': lines['pickup_pay'] += a
        elif k == 'bonus': lines['bonus'] += a
        elif k == 'tip': lines['tips'] += a
        elif k == 'fee_share': lines['fees'] += a
    kept = {c: v for c, v in lines.items() if v != 0 or c == 'trips'}
    return kept, trips, sum(lines.values())
for case in json.load(open('fixtures/payouts.json'))['cases']:
    got = payout(case['entries'])
    want = case['expect']
    if got != (want['lines'], want['tripCount'], want['amountMinor']): bad += 1; print('PAYOUT', case['id'], got, want)
# v0.11.0: zones from the server (fixtures/zones.json, contract.json#zones): point in polygon, bounds, lookup order.
def in_polygon(lat, lng, poly):
    inside = False
    for k in range(len(poly)):
        (y1, x1), (y2, x2) = poly[k], poly[(k + 1) % len(poly)]
        if (x1 == x2 == lng and min(y1, y2) <= lat <= max(y1, y2)) or (y1 == y2 == lat and min(x1, x2) <= lng <= max(x1, x2)): return True
        if (y1 > lat) != (y2 > lat):
            x = x1 + (lat - y1) * (x2 - x1) / (y2 - y1)
            if x == lng: return True
            if x > lng: inside = not inside
    return inside
zf = json.load(open('fixtures/zones.json'))
for z in zf['zones']:
    p = z['polygon']
    want = {'south': min(a for a, _ in p), 'west': min(b for _, b in p), 'north': max(a for a, _ in p), 'east': max(b for _, b in p)}
    if want != z['bounds']: bad += 1; print('ZONE BOUNDS', z['zoneId'])
    if not 3 <= len(p) <= 500 or p[0] == p[-1]: bad += 1; print('ZONE POLYGON', z['zoneId'])
def zone_at(lat, lng):
    hits = [z for z in zf['zones'] if z['bounds']['south'] <= lat <= z['bounds']['north'] and z['bounds']['west'] <= lng <= z['bounds']['east'] and in_polygon(lat, lng, z['polygon'])]
    area = lambda z: (z['bounds']['north'] - z['bounds']['south']) * (z['bounds']['east'] - z['bounds']['west'])
    hits.sort(key=lambda z: (not z['open'], z['kind'] == 'airport', area(z)))
    return hits[0]['zoneId'] if hits else None
for pt in zf['points']:
    if zone_at(pt['lat'], pt['lng']) != pt['zoneId']: bad += 1; print('ZONE AT', pt['name'], zone_at(pt['lat'], pt['lng']))
    airport = next((z['zoneId'] for z in zf['zones'] if z['kind'] == 'airport' and in_polygon(pt['lat'], pt['lng'], z['polygon'])), None)
    if airport != pt.get('airport'): bad += 1; print('AIRPORT', pt['name'], airport)
for z in c['zones']['seed']:
    if set(z['names']) != {'sv', 'fr', 'en'}: bad += 1; print('ZONE NAMES', z['zoneId'])
# v0.10.4: ONE STATUS WORD LIST (contract.json#statusWords): every code of every family has a non-empty sv, fr and en word.
def _at(path):
    o = c
    for part in path.split('.'): o = o[part]
    return o
_sw = c['statusWords']
if set(_sw['sources']) != set(_sw['families']): bad += 1; print('STATUS WORDS families', sorted(set(_sw['sources']) ^ set(_sw['families'])))
for fam, path in _sw['sources'].items():
    codes, got = _at(path), _sw['families'].get(fam, {})
    for code in codes:
        for lang in c['languages']['values']:
            if not str(got.get(code, {}).get(lang, '')).strip(): bad += 1; print('STATUS WORD MISSING', fam, code, lang)
    for code in set(got) - set(codes): bad += 1; print('STATUS WORD UNKNOWN CODE', fam, code)
for fam, codes in _sw['families'].items():
    for code, w in codes.items():
        if 'Passagerare' in w.get('sv', ''): bad += 1; print('STATUS WORD sv rider is Resenär', fam, code)
print('OK' if not bad else f'{bad} mismatches'); sys.exit(1 if bad else 0)
