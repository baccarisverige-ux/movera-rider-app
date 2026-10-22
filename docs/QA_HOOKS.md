# QA hooks (`window.movera*`)

Public GitHub Pages **release** builds do **not** expose:

- `moveraSeedActiveRide`
- `moveraClearActiveRide`
- `moveraAssignDriver`
- `moveraHoldMatching`

Hooks install only when `kDebugMode` **or** `--dart-define=MOVERA_QA=true`.

One exception is deliberate: `moveraOpenSafety` is present in **every** web
build, public Pages included (`installSafetyNavigationBridge`, installed by
`bootstrap.dart` outside the QA gate). It is navigation only: it opens the
same Safety hub the rider can open from the drawer and returns `'ok'` or
`'unavailable'`; it cannot seed rides, change matching or change Safety state.
`qa-live-rider-flow.yml` checks that it exists on public Pages. In QA builds
the gated opener installs under the same name.

`qa-live-rider-flow.yml` against public Pages skips matching/restore hook steps.
Those still require a QA-enabled web build. Do not leave hooks ungated just to
keep that workflow green; `moveraOpenSafety` above is the only hook allowed
outside the gate.

## Ride check (`moveraSimulateRideCheck`)

QA builds only (same gate). On the in-trip screen or the ride summary:

```js
moveraSimulateRideCheck('longStop', {place: 'Odenplan'})   // or stoppedMinutes
moveraSimulateRideCheck('droppedFar', {distanceMeters: 3600})
moveraSimulateRideCheck('offRoute', {distanceMeters: 2400}) // or {longerPercent: 60}
moveraSimulateRideCheck('possibleCrash')
JSON.parse(window.moveraRideCheckSnapshotJson)              // read-only state
```

The card opens at once; called on another screen, it waits for the next ride
screen. A trigger that admin turned off, or a rider who switched Ride check
off, opens nothing (same rules as live detection). Older names
(`unexpectedStop`, `routeDeviation`) still work.

Public demo builds have no QA hooks (only the `moveraOpenSafety` bridge); there, Safety › RideCheck › Try it (demo)
plays "Driver finished far from drop-off" and "Long stop".
