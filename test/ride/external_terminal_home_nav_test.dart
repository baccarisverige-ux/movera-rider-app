import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  for (final status in <RideStatus>[
    RideStatus.cancelledByDriver,
    RideStatus.cancelledBySystem,
    RideStatus.noDriverFound,
    RideStatus.paymentFailed,
    RideStatus.bookingExpired,
  ]) {
    testWidgets(
      'external ${status.name} can leave a locked ride route for Home',
      (tester) async {
        AppScope.instance.ride.restoreFromBackend(
          RideStatus.findingDriver,
          id: 'external-nav',
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: moveraNavigatorKey,
            home: const Scaffold(body: Text('home-root')),
          ),
        );

        final nav = moveraNavigatorKey.currentState!;
        nav.push(
          MaterialPageRoute<void>(
            builder: (context) => _LockedRide(
              onTerminal: () => RideNavigator.home(context, status: status),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('active-ride'), findsOneWidget);

        await tester.tap(find.text('External terminal'));
        await tester.pumpAndSettle();

        expect(find.text('active-ride'), findsNothing);
        expect(find.text('home-root'), findsOneWidget);
        expect(nav.canPop(), isFalse);
        expect(AppScope.instance.ride.status, status);
      },
    );
  }
}

class _LockedRide extends StatefulWidget {
  const _LockedRide({required this.onTerminal});

  final VoidCallback onTerminal;

  @override
  State<_LockedRide> createState() => _LockedRideState();
}

class _LockedRideState extends State<_LockedRide> {
  bool _leaving = false;

  void _leave() {
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTerminal();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _leaving,
      child: Scaffold(
        body: Column(
          children: [
            const Text('active-ride'),
            TextButton(
              onPressed: _leave,
              child: const Text('External terminal'),
            ),
          ],
        ),
      ),
    );
  }
}
