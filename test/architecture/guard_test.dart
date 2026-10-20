import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Iterable<File> dartUnder(String root) => Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  Iterable<File> presentation() =>
      dartUnder('lib/features').where((f) => f.path.contains('/presentation/'));

  // Phase 139 split parts of these screens into sibling files. Guards about
  // "the Home screen" / "the Select Ride screen" must read all of them, or
  // an isFalse check would keep passing while no longer covering moved code.
  // Each guard does its own File(...).readAsStringSync() so CI's grep-style
  // test counter (journey-integrity) still counts it.
  const homeScreenFiles = [
    'lib/features/home/presentation/home.dart',
    'lib/features/home/presentation/home_map_style.dart',
    'lib/features/home/presentation/widgets/home_map_layer.dart',
  ];

  const selectRideScreenFiles = [
    'lib/features/ride_selection/presentation/select_ride.dart',
    'lib/features/ride_selection/presentation/select_ride_filter.dart',
    'lib/features/ride_selection/presentation/select_ride_geometry.dart',
    'lib/features/ride_selection/presentation/widgets/select_ride_route_canvas.dart',
  ];

  test('presentation does not import raw http or shared_preferences', () {
    for (final file in presentation()) {
      final src = file.readAsStringSync();
      expect(
        src.contains("package:http/http.dart"),
        isFalse,
        reason: file.path,
      );
      expect(
        src.contains("package:shared_preferences/shared_preferences.dart"),
        isFalse,
        reason: file.path,
      );
      expect(src.contains('sk_live'), isFalse, reason: file.path);
      expect(
        src.contains("package:movera_rider/core/api/api_client.dart"),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('screens do not invent their own route polyline', () {
    // RoutingService is the single seam a real Directions provider will land
    // in. A screen that builds Polyline(points: [pickup, destination]) itself
    // would keep drawing a straight line long after that seam returns real
    // road geometry, so features go through routePolyline() instead.
    // Word-boundary matched so routePolyline() itself does not trip it.
    final handBuilt = RegExp(r'(?<![A-Za-z])Polyline(Id)?\(');
    for (final file in dartUnder('lib/features')) {
      final src = file.readAsStringSync();
      expect(handBuilt.hasMatch(src), isFalse, reason: file.path);
    }
  });

  test('no SharedPreferences token storage', () {
    final token = File('lib/core/auth/token_store.dart').readAsStringSync();
    expect(token.contains("package:shared_preferences"), isFalse);
    final secure = File(
      'lib/core/auth/secure_token_store.dart',
    ).readAsStringSync();
    expect(secure.contains("package:shared_preferences"), isFalse);
  });

  test('finding driver assignment is not a widget Timer', () {
    final ui = File(
      'lib/features/finding_driver/presentation/finding_drivers.dart',
    ).readAsStringSync();
    expect(ui.contains('Timer(Duration(seconds: 12)'), isFalse);
    expect(ui.contains("MarkerId('car-a')"), isFalse);
    expect(ui.contains('Confirming your ride'), isFalse);
  });

  test('obsolete confirming and cancel dialogs are gone', () {
    expect(
      File(
        'lib/features/finding_driver/presentation/cancel_ride.dart',
      ).existsSync(),
      isFalse,
    );
    for (final file in dartUnder('lib')) {
      final src = file.readAsStringSync();
      expect(src.contains('Confirming your ride'), isFalse, reason: file.path);
      expect(
        src.contains('RideCancellationDialog'),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('sheets use MoveraSheet instead of showModalBottomSheet', () {
    for (final file in dartUnder('lib')) {
      if (file.path.contains('movera_sheet.dart')) continue;
      final src = file.readAsStringSync();
      expect(src.contains('showModalBottomSheet'), isFalse, reason: file.path);
    }
  });

  test('page transitions use shared motion tokens', () {
    final src = File(
      'lib/shared/widgets/navigation_transition.dart',
    ).readAsStringSync();
    expect(src.contains('milliseconds: 1000'), isFalse);
    expect(src.contains('MoveraDurations'), isTrue);
    expect(src.contains('child: page'), isFalse);
  });

  test('sheet coordinator stays free of ride matching', () {
    final src = File(
      'lib/features/ride_booking/application/sheet_coordinator.dart',
    ).readAsStringSync();
    expect(src.contains('ApiClient'), isFalse);
    expect(src.contains('confirmPriceIncrease'), isFalse);
    expect(src.contains('MockRideRealtime'), isFalse);
  });

  test('home does not own ride restoration', () {
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(home.contains('_restoreActiveRide'), isFalse);
    expect(home.contains('RideSnapshotStore'), isFalse);
    // Phase 143: ride_restore_coordinator.dart builds Home, so Home must not
    // import it back (that was a two-way import cycle). Home reads the
    // interrupted-search flag from the leaf SearchInterruptedNotice instead.
    expect(home.contains('ride_restore_coordinator.dart'), isFalse);
  });

  test('home does not draw a trip polyline', () {
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(home.contains('Polyline('), isFalse);
    expect(home.contains('polylines:'), isFalse);
  });

  test('waiting screen does not markArriving on open', () {
    final ui = File(
      'lib/features/active_ride/presentation/waiting_for_driver.dart',
    ).readAsStringSync();
    expect(ui.contains('markArriving'), isFalse);
  });

  test('never disposes GoogleMapController', () {
    for (final file in dartUnder('lib')) {
      final src = file.readAsStringSync();
      expect(
        src.contains('GoogleMapController.dispose'),
        isFalse,
        reason: file.path,
      );
      expect(
        RegExp(
          r'_mapController\?\.dispose|_mapController\.dispose',
        ).hasMatch(src),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('presentation has no catalog fare table', () {
    for (final file in presentation()) {
      final src = file.readAsStringSync();
      expect(src.contains("'economy': 259"), isFalse, reason: file.path);
    }
  });

  // ARCH-17 / CODE-16: every layering rule that needs the import graph lives
  // in this one source-reading case, so the journey-integrity budget does not
  // grow with each rule.
  test('layer imports respect boundaries and no catch is silently empty', () {
    final banned = RegExp(r'package:movera_rider/features/[^/]+/data/');
    for (final file in presentation()) {
      final src = file.readAsStringSync();
      expect(banned.hasMatch(src), isFalse, reason: file.path);
    }

    final directive = RegExp(
      r"^\s*(?:import|export)\s+'([^']+)'",
      multiLine: true,
    );
    List<String> importsOf(String src) =>
        [for (final m in directive.allMatches(src)) m.group(1)!];
    String norm(String path) => path.replaceAll(r'\', '/');

    // core is feature-agnostic and never reaches back into the DI container.
    for (final file in dartUnder('lib/core')) {
      for (final uri in importsOf(file.readAsStringSync())) {
        expect(
          uri.startsWith('package:movera_rider/features/') ||
              uri == 'package:movera_rider/app/di.dart',
          isFalse,
          reason: '${norm(file.path)} imports $uri (core -> features/di)',
        );
      }
    }

    // DI knows concrete services, not screens.
    for (final uri in importsOf(File('lib/app/di.dart').readAsStringSync())) {
      expect(
        uri.contains('/presentation/'),
        isFalse,
        reason: 'lib/app/di.dart imports $uri (di -> presentation)',
      );
    }

    // Application services do not import screens. These navigation
    // coordinators predate the rule; the list may only shrink, so a file
    // that no longer needs its exemption fails here until it is removed.
    const legacyApplicationToPresentation = {
      'lib/features/notifications/application/notification_navigation.dart',
      'lib/features/reservations/application/scheduled_ride_checkout.dart',
      'lib/features/ride_booking/application/ride_restore_coordinator.dart',
    };
    final offenders = <String>{};
    for (final file in dartUnder('lib/features')) {
      final path = norm(file.path);
      if (!path.contains('/application/')) continue;
      final hits = importsOf(file.readAsStringSync())
          .where((uri) => uri.contains('/presentation/'));
      if (hits.isNotEmpty) offenders.add(path);
    }
    expect(
      offenders.difference(legacyApplicationToPresentation),
      isEmpty,
      reason: 'application -> presentation import',
    );
    expect(
      legacyApplicationToPresentation.difference(offenders),
      isEmpty,
      reason: 'exemption no longer needed; remove it from the list',
    );

    // An ignored error either logs or says why it is safe to ignore.
    final emptyCatch = RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}');
    for (final file in dartUnder('lib')) {
      expect(
        emptyCatch.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${norm(file.path)} has an empty catch',
      );
    }
  });

  test('presentation does not construct API, booking, or payment clients', () {
    for (final file in presentation()) {
      final src = file.readAsStringSync();
      expect(src.contains('ApiClient('), isFalse, reason: file.path);
      expect(src.contains('InProcessMockClient('), isFalse, reason: file.path);
      expect(src.contains('MockPaymentGateway('), isFalse, reason: file.path);
      expect(src.contains('MockRideRealtime('), isFalse, reason: file.path);
    }
  });

  test('home does not import address repository', () {
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(home.contains('home_repository.dart'), isFalse);
    expect(home.contains('HomeAddressRepository'), isFalse);
  });

  test('select ride widget is not the source of ride/payment truth', () {
    final ui = selectRideScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(ui.contains("String _selectedRideId"), isFalse);
    expect(ui.contains('int _selectedPayment'), isFalse);
    expect(ui.contains('DateTime? _scheduledFor'), isFalse);
    expect(ui.contains('ValueKey(\'select-ride-map\')'), isTrue);
    expect(ui.contains('bottom: minSheet'), isTrue);
  });

  test('waiting screen does not hardcode driver plate', () {
    final ui = File(
      'lib/features/active_ride/presentation/waiting_for_driver.dart',
    ).readAsStringSync();
    expect(ui.contains('"L - 2323 F"'), isFalse);
    expect(ui.contains('Merle Feeney'), isFalse);
    expect(ui.contains('5 mins'), isFalse);
    expect(ui.contains('Confirming your ride'), isFalse);
  });

  test('home does not own map overlay set fields', () {
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(home.contains('Set<Marker> _markers ='), isFalse);
    expect(home.contains('Set<Circle> _locationCircles ='), isFalse);
    expect(home.contains('Set<Polygon> _locationDirection ='), isFalse);
    expect(home.contains('HomeAddressRepository'), isFalse);
  });

  test('web heading start is idempotent and gesture-armed', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html.contains('moveraStartHeading'), isTrue);
    expect(html.contains('moveraHeadingStartPromise'), isTrue);
    expect(html.contains('moveraInjectHeading'), isTrue);
    expect(html.contains('moveraStopHeading'), isTrue);
    expect(html.contains('moveraArmHeadingFromGesture'), isTrue);
    expect(html.contains('moveraRequestHeadingFromGesture'), isTrue);
    expect(html.contains("addEventListener('pointerdown', arm, true)"), isTrue);
    expect(html.contains("addEventListener('touchstart', arm, true)"), isTrue);
    expect(html.contains("addEventListener('touchend', arm, true)"), isTrue);
    expect(
      html.contains('DeviceOrientationEvent.requestPermission().then'),
      isTrue,
    );
    expect(html.contains('webkitCompassHeading'), isTrue);
    expect(html.contains('moveraScreenAngle'), isTrue);
    expect(html.contains('moveraHeadingDebug'), isTrue);
    expect(html.contains('moveraHeadingSnapshot'), isTrue);
    expect(html.contains('moveraBrokenStage'), isTrue);
    expect(html.contains('in-app WKWebView'), isTrue);
    // A failed first gesture must not permanently block a later real tap.
    expect(
      html.contains(
        'if (window.moveraHeadingStarted || window._moveraGestureAsked) return;',
      ),
      isFalse,
    );
    expect(html.contains("addEventListener('pagehide'"), isFalse);
    expect(html.contains('movera-hd'), isFalse);
    expect(html.contains('TAP THIS PANEL'), isFalse);
    expect(html.contains('moveraInstallHeadingOverlay'), isFalse);
    // Phase 47: geocoding goes through the authenticated Movera API only.
    // A leftover moveraGeocodeAddress kept sending typed addresses to public
    // Nominatim and crashed on the cache Phase 47 removed.
    expect(html.contains('nominatim'), isFalse);
    expect(html.contains('moveraGeocodeAddress'), isFalse);
    expect(html.contains('moveraGeoCache'), isFalse);
  });

  test('promotions come only from the server and never invent content', () {
    // The owner brought the promotion ticket back (Home + ride list). It must
    // show only what the admin panel created for this rider.
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('in_process_mock_client.dart'));
    for (final file in libFiles) {
      expect(
        RegExp(r"'\d+% off your next").hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} hardcodes a promotion title',
      );
    }
    final ticket = File(
      'lib/features/promotions/presentation/promotion_ticket.dart',
    ).readAsStringSync();
    expect(ticket.contains('RiderPromotion promotion'), isTrue);
    expect(ticket.contains('Icons.close'), isFalse, reason: 'no close button');
    final home = homeScreenFiles
        .map((p) => File(p).readAsStringSync())
        .join('\n');
    expect(home.contains('AppScope.instance.promotion.active'), isTrue);
    expect(
      File('lib/core/feature_flags/feature_flags.dart').readAsStringSync(),
      isNot(contains('enablePromotions')),
    );
  });

  test('dead XEntity scaffolds and driver-part zips are gone', () {
    const stubs = [
      'lib/features/auth/domain/auth.dart',
      'lib/features/fare/domain/fare.dart',
      'lib/features/payments/domain/payments.dart',
      'lib/features/pickup/domain/pickup.dart',
      'lib/features/onboarding/domain/onboarding.dart',
      'lib/features/ride_booking/domain/entities/driver.dart',
    ];
    for (final path in stubs) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    final tracked = Process.runSync('git', ['ls-files']).stdout as String;
    expect(tracked.contains('driver-part-'), isFalse);
  });


  test('side menu lists only currently reachable production destinations', () {
    final source = File(
      'lib/features/home/presentation/side_menu.dart',
    ).readAsStringSync();
    // Round 4: the labels live in l10n; check the English text the menu
    // shows next to its code.
    final english = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final menu = [
      source,
      for (final m in RegExp(r'l10n\.(\w+)').allMatches(source))
        '${english[m.group(1)]}',
    ].join('\n');
    expect(menu.contains('Promotions'), isFalse);
    expect(menu.contains('Scheduled Rides'), isFalse);
    expect(menu.contains('Subscriptions'), isFalse);
    expect(menu.contains('Expense Your Rides'), isFalse);
    expect(menu.contains('Wallet'), isTrue);
    expect(menu.contains('Ride History'), isTrue);
    expect(menu.contains('Payments'), isTrue);
    expect(menu.contains('Safety'), isTrue);
    expect(menu.contains('Support'), isTrue);
    // Referrals have no live destination yet, so the drawer must hide them.
    expect(menu.contains('Invite Friends'), isFalse);
    expect(menu.contains('About'), isTrue);
    expect(menu.contains('Become a driver'), isFalse);
  });

  test('safety presentation stays off the data and platform layers', () {
    for (final file in dartUnder('lib/features/safety/presentation')) {
      final src = file.readAsStringSync();
      expect(
        src.contains("package:http/http.dart"),
        isFalse,
        reason: file.path,
      );
      expect(src.contains('shared_preferences'), isFalse, reason: file.path);
      expect(src.contains('ApiClient'), isFalse, reason: file.path);
      expect(src.contains('PreferencesStore'), isFalse, reason: file.path);
      expect(src.contains('url_launcher'), isFalse, reason: file.path);
      expect(src.contains('tel:112'), isFalse, reason: file.path);
      expect(src.contains('InProcessMockClient'), isFalse, reason: file.path);
      expect(
        src.contains("package:movera_rider/features/safety/data/"),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('home does not add a compass permission screen', () {
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(home.contains('Enable compass'), isFalse);
    expect(home.contains('Motion permission'), isFalse);
    expect(home.contains('Device orientation'), isFalse);
  });

  test('select ride does not keep parallel quote expiry state', () {
    final ui = selectRideScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(ui.contains('Map<String, DateTime> _quoteExpires'), isFalse);
    expect(ui.contains('Map<String, String> _quoteIds'), isFalse);
  });

  test('reservation presentation stays off the data layer and Uber copy', () {
    for (final file in dartUnder('lib/features/reservations/presentation')) {
      final src = file.readAsStringSync();
      expect(
        src.contains("package:movera_rider/features/reservations/data/"),
        isFalse,
        reason: file.path,
      );
      expect(src.contains('UberX'), isFalse, reason: file.path);
      expect(src.contains('Uber '), isFalse, reason: file.path);
      expect(src.contains('SEK 160'), isFalse, reason: file.path);
      expect(src.contains('SEK 240'), isFalse, reason: file.path);
      expect(
        src.contains("We'll send your driver by"),
        isFalse,
        reason: file.path,
      );
      expect(src.contains('showModalBottomSheet'), isFalse, reason: file.path);
    }
  });

  test('old scheduled confirmation screens are removed', () {
    expect(
      File(
        'lib/features/scheduled_rides/presentation/ride_confirmed.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/ride_pending.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/confirm_booking.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/add_note.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('on-demand finding driver is not rewritten by reservations', () {
    final finding = File(
      'lib/features/finding_driver/presentation/finding_drivers.dart',
    ).readAsStringSync();
    expect(finding.contains('ReservationController'), isFalse);
    expect(finding.contains('createReservation'), isFalse);
  });

  test('scheduled mode never enters Finding Driver; now mode still does', () {
    final src = File(
      'lib/features/ride_selection/presentation/select_ride.dart',
    ).readAsStringSync();
    final scheduledStart = src.indexOf('Future<void> _bookScheduled');
    final nowStart = src.indexOf('void _bookNow()');
    final bookStart = src.indexOf('void _book()');
    expect(scheduledStart, greaterThan(0));
    expect(bookStart, greaterThan(scheduledStart));
    expect(nowStart, greaterThan(bookStart));
    final scheduled = src.substring(scheduledStart, nowStart);
    expect(scheduled.contains('FindingDrivers'), isFalse);
    expect(scheduled.contains('submitFinding'), isFalse);
    expect(scheduled.contains('ScheduledRideCheckout.run'), isTrue);
    expect(scheduled.contains('_reservations.create'), isFalse);
    expect(src.contains('ScheduleDateTimeSelector.choose'), isTrue);
    expect(src.contains('_chooseLater'), isTrue);
    final now = src.substring(nowStart);
    expect(now.contains('FindingDrivers'), isTrue);
    expect(now.contains('submitFinding'), isTrue);
    expect(now.contains('showQuickRideNotesSheet'), isFalse);
    // The notes block was removed from categories (owner request).
    expect(src.contains('Anything we should know?'), isFalse);
    expect(now.contains('ScheduledRideBooking.confirm'), isFalse);
    expect(now.contains('_reservations.create'), isFalse);
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(home.contains('RideScheduledPage.open'), isTrue);
    expect(home.contains('FindingDrivers'), isFalse);
    expect(home.contains('WaitingForDriver'), isFalse);
  });

  test('return ride reuses the shared SelectRide category selector', () {
    final planReturn = File(
      'lib/features/reservations/presentation/plan_return_ride.dart',
    ).readAsStringSync();
    expect(planReturn.contains('SelectRide.forReturnRide'), isTrue);
    expect(planReturn.contains('FindingDrivers'), isFalse);
    final selectRide = File(
      'lib/features/ride_selection/presentation/select_ride.dart',
    ).readAsStringSync();
    expect(selectRide.contains('factory SelectRide.forReturnRide'), isTrue);
    expect(selectRide.contains('bookingMode: BookingMode.scheduled'), isTrue);
  });

  test('history Schedule a ride still opens Plan your ride; Home Later uses Where to', () {
    final history = File(
      'lib/features/history/presentation/ride_history.dart',
    ).readAsStringSync();
    expect(history.contains('ScheduleRide()'), isTrue);
    expect(history.contains('SelectRide('), isFalse);
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(home.contains('bookingMode: BookingMode.now'), isTrue);
    // Book for later follows the Book now screens: Where to → date & time →
    // scheduled categories → Set pickup. The old Plan your ride screen is
    // only for editing a reservation and the history entry.
    expect(home.contains('const ScheduleRide()'), isFalse);
    expect(home.contains("_showRouteAddressPicker(initialField: 'destination', scheduled: true)"), isTrue);
    expect(home.contains('ScheduleDateTimeSelector.choose('), isTrue);
    expect(home.contains('BookingMode.scheduled'), isTrue);
    expect(home.contains('_handleDestinationTap'), isTrue);
    expect(home.contains('HomeReservationChrono'), isTrue);
    expect(home.contains('_PickupMapPickerPage'), isFalse);
    expect(home.contains('ConfirmPickupSpot.open'), isTrue);
    expect(home.contains('AccountHomePage'), isTrue);
    expect(home.contains('Uber account'), isFalse);
  });

  test('book now always opens Confirm pickup; GPS only prefills', () {
    final home = homeScreenFiles.map((p) => File(p).readAsStringSync()).join('\n');
    expect(
      home.contains('Book now always confirms pickup; GPS only prefills.'),
      isTrue,
    );
    expect(home.contains('if (!pickupConfirmedOnMap)'), isFalse);
    expect(
      home.contains(
        'var pickupPosition = _tripPickupLatLng ?? _currentLatLng;',
      ),
      isFalse,
    );
    expect(home.contains('bookingMode: BookingMode.now'), isTrue);
    expect(home.contains('_openPickupMapPicker'), isTrue);
    final selectRide = File(
      'lib/features/ride_selection/presentation/select_ride.dart',
    ).readAsStringSync();
    final nowStart = selectRide.indexOf('void _bookNow()');
    final now = selectRide.substring(nowStart);
    expect(now.contains('FindingDrivers'), isTrue);
    // Set pickup opens after Book every time, before the search starts.
    expect(selectRide.contains('SetPickupPage.open('), isTrue);
    expect(now.indexOf('_openSetPickup('), lessThan(now.indexOf('FindingDrivers(')));
    expect(now.contains('AddCardPage.open('), isTrue);
  });

  test(
    'book now two-path e2e covers GPS on, GPS off, back, and Finding Driver',
    () {
      final src = File(
        'test/ride/book_now_two_paths_e2e_test.dart',
      ).readAsStringSync();
      expect(src.contains('GPS available still opens Confirm pickup'), isTrue);
      expect(
        src.contains('GPS unavailable still opens Confirm pickup'),
        isTrue,
      );
      expect(
        src.contains('Back on Confirm pickup returns without booking'),
        isTrue,
      );
      expect(src.contains('Select Movera starts Finding Driver'), isTrue);
      expect(
        src.contains('Select Movera submitFinding marks Finding Driver'),
        isTrue,
      );
      expect(src.contains('Book later stays off Finding Driver'), isTrue);
      expect(src.contains('Connecting you with nearby drivers'), isTrue);
    },
  );

  test(
    'Later/Schedule ride goes Plan your ride → calendar → shared categories',
    () {
      // Round 4: screen copy lives in l10n; read each source with the
      // English text of the messages it uses.
      final english = jsonDecode(
        File('lib/l10n/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      String withEnglish(String path) {
        final source = File(path).readAsStringSync();
        return [
          source,
          for (final m in RegExp(r'l10n\.(\w+)').allMatches(source))
            '${english[m.group(1)]}',
        ].join('\n');
      }

      final schedule = withEnglish(
        'lib/features/scheduled_rides/presentation/schedule_ride.dart',
      );
      expect(schedule.contains('Plan your ride'), isTrue);
      expect(schedule.contains('ConfirmPickupSpot'), isTrue);
      expect(schedule.contains('ScheduleDateTimeSelector'), isTrue);
      expect(schedule.contains('openScheduledCategorySelector'), isTrue);
      expect(schedule.contains('ScheduleAddNote'), isFalse);
      expect(schedule.contains('ScheduleConfirmBooking'), isFalse);
      final gate = File(
        'lib/features/reservations/presentation/scheduled_category_gate.dart',
      ).readAsStringSync();
      expect(gate.contains('bookingMode: BookingMode.scheduled'), isTrue);
      expect(gate.contains('lockBookingMode: true'), isTrue);
      expect(gate.contains('FindingDrivers'), isFalse);
      expect(gate.contains('SelectRide('), isTrue);
      expect(gate.contains('untilHome: true'), isTrue);
      expect(gate.contains('editingReservationId'), isTrue);
      final details = File(
        'lib/features/reservations/presentation/upcoming_reservation.dart',
      ).readAsStringSync();
      expect(details.contains('showReservationTimeSheet'), isFalse);
      expect(details.contains('ScheduleRide(editing:'), isTrue);
      expect(details.contains('ReservationEditButton'), isTrue);
      expect(
        withEnglish(
          'lib/features/reservations/presentation/reservation_widgets.dart',
        ).contains('Edit reservation'),
        isTrue,
      );
    },
  );

  test(
    'scheduled booking flow test proves CTA, Ride scheduled, and no Finding Driver',
    () {
      final src = File(
        'test/reservations/scheduled_booking_flow_test.dart',
      ).readAsStringSync();
      expect(src.contains('Schedule Movera'), isTrue);
      expect(src.contains('Select Movera'), isTrue);
      expect(src.contains('Ride scheduled'), isTrue);
      expect(src.contains('FindingDriverController.active'), isTrue);
      expect(src.contains('Connecting you with nearby drivers'), isTrue);
      expect(src.contains('ScheduledRideBooking.confirm'), isTrue);
      expect(src.contains('ScheduleDateTimeSelector.choose'), isTrue);
      expect(src.contains('When should we pick you up Continue'), isTrue);
      expect(src.contains('editing a reservation keeps the same id'), isTrue);
      expect(src.contains('checkout draft does not create'), isTrue);
      expect(
        src.contains('edit hydrates the saved payment instead of defaulting'),
        isTrue,
      );
    },
  );

  test('scheduled checkout confirms after pickup is already set', () {
    final checkout = File(
      'lib/features/reservations/application/scheduled_ride_checkout.dart',
    ).readAsStringSync();
    expect(checkout.contains('ConfirmPickupSpot'), isFalse);
    expect(checkout.contains('ReservationReviewPage'), isFalse);
    expect(checkout.contains('ReviewChangesPage'), isTrue);
    expect(checkout.contains('showReservationBookedPopup'), isTrue);
    expect(checkout.contains('ScheduledRideBooking.confirm'), isTrue);
    expect(checkout.contains('FindingDrivers'), isFalse);
    expect(checkout.contains('submitFinding'), isFalse);
    final pickup = File(
      'lib/features/pickup/presentation/confirm_pickup_spot.dart',
    ).readAsStringSync();
    // Round 4: the default label comes from l10n ("Confirm pickup").
    expect(
      pickup.contains('widget.confirmLabel ?? context.l10n.confirmPickup'),
      isTrue,
    );
    final finding = File(
      'lib/features/finding_driver/presentation/finding_drivers.dart',
    ).readAsStringSync();
    expect(finding.contains('scheduledSummary'), isFalse);
    expect(finding.contains('confirmLabel'), isFalse);
  });

  test(
    'book now uses the shared coordinator, CTA lock, and confirmed pickup',
    () {
      final repo = File(
        'lib/features/booking/data/booking_repository.dart',
      ).readAsStringSync();
      expect(repo.contains('BookingCoordinator()'), isFalse);
      expect(repo.contains('AppScope.instance.booking'), isTrue);
      final src = File(
        'lib/features/ride_selection/presentation/select_ride.dart',
      ).readAsStringSync();
      expect(src.contains('bool _bookingInFlight'), isTrue);
      expect(src.contains('if (_bookingInFlight) return'), isTrue);
      expect(src.contains('onTap: _bookingInFlight ? null : _book'), isTrue);
      expect(src.contains('selectPaymentNamed'), isTrue);
      final nowStart = src.indexOf('void _bookNow()');
      final buildStart = src.indexOf(
        'Widget build(BuildContext context)',
        nowStart,
      );
      expect(nowStart, greaterThan(0));
      expect(buildStart, greaterThan(nowStart));
      final now = src.substring(nowStart, buildStart);
      expect(now.contains('pickupAddress: _pickupAddress'), isTrue);
      expect(now.contains('pickupAddress: widget.pickupAddress'), isFalse);
      expect(now.contains('FindingDriverController.active'), isTrue);
      expect(now.contains('FindingDrivers'), isTrue);
      expect(now.contains('submitFinding'), isTrue);
      final schedule = File(
        'lib/features/scheduled_rides/presentation/schedule_ride.dart',
      ).readAsStringSync();
      expect(schedule.contains('bool _nextInFlight'), isTrue);
      expect(schedule.contains('if (_nextInFlight) return'), isTrue);
      final history = File(
        'lib/features/history/data/on_demand_ride_history_store.dart',
      ).readAsStringSync();
      expect(history.contains('archiveCancelledThenClear'), isTrue);
    },
  );
}
