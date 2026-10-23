"""Reference engine for contract.json: replays fixtures/scenarios.json, events.json, money.json, cancel_fees.json, pickup_pay.json and surge.json.
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
print('OK' if not bad else f'{bad} mismatches'); sys.exit(1 if bad else 0)
