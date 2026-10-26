import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  test('dead multi-megabyte map assets are not shipped', () {
    expect(File('assets/images/map.png').existsSync(), isFalse);
    expect(File('assets/images/id.png').existsSync(), isFalse);
    expect(
      File('assets/images/earning_stats_card_img.png').existsSync(),
      isFalse,
    );
  });

  test('bundled rasters stay within the Phase 5 payload budget', () {
    var imagesBytes = 0;
    var largest = 0;
    var largestPath = '';
    for (final entity in Directory('assets').listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (!RegExp(r'\.(png|jpg|jpeg|webp)$').hasMatch(path)) continue;
      final size = entity.lengthSync();
      imagesBytes += size;
      if (size > largest) {
        largest = size;
        largestPath = path;
      }
    }
    expect(
      largest,
      lessThan(200 * 1024),
      reason: '$largestPath is $largest bytes',
    );
    expect(imagesBytes, lessThan(4 * 1024 * 1024));
  });

  test('used oversized photos were converted to WebP', () {
    expect(
      File('assets/images/advance_booking_driver.webp').existsSync(),
      isTrue,
    );
    expect(File('assets/images/pin_verification.webp').existsSync(), isTrue);
    expect(File('assets/images/wallet_rider_3d.webp').existsSync(), isTrue);
    expect(File('assets/images/rides/movera.webp').existsSync(), isTrue);
    expect(
      File('assets/images/advance_booking_driver.png').existsSync(),
      isFalse,
    );
  });

  test(
    'resume reconnect does not reset an unmatched ride subscription',
    () async {
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      rt.subscribe('ride-1');
      rt.emit(RideStatus.findingDriver, sequence: 7);
      await rt.reconnectAndResync('ride-1');
      rt.subscribe('ride-1');
      expect(rt.lastStatus, RideStatus.findingDriver);
      rt.dispose();
    },
  );
}
