"""Reference engine for contract.json: replays fixtures/scenarios.json and fixtures/events.json.
Each app's contract tests must give the same answers."""
import json, sys
c = json.load(open('contract.json'))
term = set(c['tripStatus']['terminal'])
def step(status, command, actor, kind):
    for t in c['transitions']:
        if t['command'] == command and t['actor'] == actor and status in t['from'] and t.get('when', kind) == kind:
            return t['to']
    return None
bad = 0
for s in json.load(open('fixtures/scenarios.json'))['scenarios']:
    st = 'draft'
    for cmd, actor, expect in s['steps']:
        nxt = step(st, cmd, actor, s['kind'])
        got = nxt if nxt else 'invalid_transition'
        if got != expect:
            bad += 1; print('SCENARIO', s['id'], cmd, actor, 'from', st, 'expected', expect, 'got', got)
        if nxt: st = nxt
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
print('OK' if not bad else f'{bad} mismatches'); sys.exit(1 if bad else 0)
