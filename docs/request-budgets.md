# Rider app request budgets (global plan step 62, T3)

Measured by `test/perf/request_budget/request_budget_test.dart` (harness:
`request_budget_harness.dart`). Each state runs the app's real request owners
over one real `ApiClient` whose `http.Client` counts every request; the clock is
fake (`fake_async`). Steady rate = requests in minutes 1-11 after entering the
state, divided by 10. "On entry" = requests in the first second (the burst when
the state opens). SSE streams answer a heartbeat every 15 s, so an open stream
costs one request on entry and nothing after.

The test fails when a state sends more than its budget + max(10 %, 0.5/min) on
any endpoint (an endpoint not listed has budget 0). **A PR that raises a number
changes this file and `budgets` in the test, and says why.**

What runs in each state (the code the harness drives):

| State | Request owners |
|---|---|
| homeIdle | config watch (`lib/core/config/api_rider_config_repository.dart`), trip watch on Home (`lib/features/ride_booking/application/rider_trip_watch.dart`, 8 s), presence ping (`lib/features/home/application/home_presence.dart`, 45 s) |
| quoting | config watch, trip watch on Home, cars near the pickup (`lib/features/ride_selection/application/nearby_cars_controller.dart`, server `refreshSeconds`, the fake server answers the contract's 5 s, contract.json#riderNearby); presence stops (Home covered) |
| searching | config watch, trip watch (ride on screen: booked-driver check, 8 s), trip follow (`lib/core/realtime/api_ride_realtime.dart`: one read + SSE) |
| driverArriving / onTrip | as searching + unread badge poll (`lib/features/messages/application/messages_controller.dart`, 10 s, started in `waiting_for_driver.dart:237`) |
| tripFinished | config watch, trip watch (receipt counts as a ride on screen), trip follow (`ride_completed.dart:137`) |
| background | config watch stream only (trip watch stops, `app_lifecycle.dart:58`) |
| homeConfigStreamDown | homeIdle with `/rider/config/stream` answering 503 |
| arrivingTripStreamDown | driverArriving with the trip stream answering 503 (poll fallback 10 s, stream retry backoff 5 s doubling to 60 s) |

## Table (state × endpoint × per minute)

| State | Endpoint | Budget /min | Measured /min | On entry |
|---|---|---|---|---|
| homeIdle | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| homeIdle | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| homeIdle | `GET /api/v1/rider/nearby-vehicles` | 1.4 | 1.30 | 1 |
| homeIdle | `GET /api/v1/rider/trips/active` | 7.5 | 7.50 | 0 |
| homeIdle | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| quoting | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| quoting | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| quoting | `GET /api/v1/rider/nearby-vehicles` | 12.0 | 12.00 | 1 |
| quoting | `GET /api/v1/rider/trips/active` | 7.5 | 7.50 | 0 |
| quoting | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| searching | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| searching | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| searching | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| searching | `GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived` | 7.5 | 7.50 | 0 |
| searching | `GET /api/v1/trips/{tripId}` | 0 | 0.00 | 1 |
| searching | `GET /api/v1/trips/{tripId}/events (SSE open)` | 0 | 0.00 | 1 |
| driverArriving | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| driverArriving | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| driverArriving | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| driverArriving | `GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived` | 7.5 | 7.50 | 0 |
| driverArriving | `GET /api/v1/trips/{tripId}` | 0 | 0.00 | 1 |
| driverArriving | `GET /api/v1/trips/{tripId}/events (SSE open)` | 0 | 0.00 | 1 |
| driverArriving | `GET /api/v1/trips/{tripId}/messages` | 6.0 | 6.00 | 1 |
| onTrip | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| onTrip | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| onTrip | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| onTrip | `GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived` | 7.5 | 7.50 | 0 |
| onTrip | `GET /api/v1/trips/{tripId}` | 0 | 0.00 | 1 |
| onTrip | `GET /api/v1/trips/{tripId}/events (SSE open)` | 0 | 0.00 | 1 |
| onTrip | `GET /api/v1/trips/{tripId}/messages` | 6.0 | 6.00 | 1 |
| tripFinished | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| tripFinished | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| tripFinished | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| tripFinished | `GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived` | 7.5 | 7.50 | 0 |
| tripFinished | `GET /api/v1/trips/{tripId}` | 0 | 0.00 | 1 |
| tripFinished | `GET /api/v1/trips/{tripId}/events (SSE open)` | 0 | 0.00 | 1 |
| background | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| background | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| homeConfigStreamDown | `GET /api/v1/rider/config` | 12.0 | 12.00 | 1 |
| homeConfigStreamDown | `GET /api/v1/rider/config/stream (SSE open)` | 12.0 | 12.00 | 1 |
| homeConfigStreamDown | `GET /api/v1/rider/nearby-vehicles` | 1.4 | 1.30 | 1 |
| homeConfigStreamDown | `GET /api/v1/rider/trips/active` | 7.5 | 7.50 | 0 |
| homeConfigStreamDown | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| arrivingTripStreamDown | `GET /api/v1/rider/config` | 0 | 0.00 | 1 |
| arrivingTripStreamDown | `GET /api/v1/rider/config/stream (SSE open)` | 0 | 0.00 | 1 |
| arrivingTripStreamDown | `GET /api/v1/rider/trips?kind=scheduled` | 0 | 0.00 | 1 |
| arrivingTripStreamDown | `GET /api/v1/rider/trips?kind=scheduled&status=driver_to_pickup,arrived` | 7.5 | 7.50 | 0 |
| arrivingTripStreamDown | `GET /api/v1/trips/{tripId}` | 6.0 | 6.00 | 1 |
| arrivingTripStreamDown | `GET /api/v1/trips/{tripId}/events (SSE open)` | 1.1 | 1.00 | 1 |
| arrivingTripStreamDown | `GET /api/v1/trips/{tripId}/messages` | 6.0 | 6.00 | 1 |

## Totals per state (steady, per minute)

| State | Requests /min |
|---|---|
| homeIdle | 8.80 |
| quoting | 19.50 |
| searching | 7.50 |
| driverArriving | 13.50 |
| onTrip | 13.50 |
| tripFinished | 7.50 |
| background | 0.00 |
| homeConfigStreamDown | 32.80 |
| arrivingTripStreamDown | 20.50 |

## Notes

- The booked-driver check (`GET /rider/trips?kind=scheduled&status=…`) runs every
  8 s for the whole ride (searching, arriving, on trip, receipt):
  `rider_trip_watch.dart:91` + `:128`. It is the largest steady cost of a ride.
- `/rider/config/stream` refused: the watch reconnects every 5 s with no backoff
  and reads the config each time (`api_rider_config_repository.dart:279`): 24
  requests a minute per rider while the server is down or restarting.
- **Not covered: searching after 3 min.** After the search timeout the finding
  screen asks the server every 15 s (`finding_driver_controller.dart:96-97`,
  `finding_driver_controller_search.dart:42-55`): +4/min, so searching late is
  11.5/min (step 60 uses 11.5). Not driven here: the controller needs the whole
  AppScope / widget setup.
- Each trip event (`rider_trip_changed` on `/rider/config/stream`) costs +2
  requests (booked list + check, `rider_trip_watch.dart:79-85`), as in step 60;
  not counted in the steady rates.
- Not in this table (one-off, not timed): the quote request(s) on Select ride
  and the requote at quote expiry (`select_ride_quotes.dart:21`); the open Chat screen (3 s poll,
  `messages_controller.dart:48`); resume bursts.
