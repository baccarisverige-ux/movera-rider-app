import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_photo.dart';

/// The driver's round picture: the approved photo from the server
/// ([DriverPhotos], G2-D3), else a bundled demo picture, else [fallback]
/// (the Movera avatar: initial or person icon).
class DriverPhotoAvatar extends StatefulWidget {
  const DriverPhotoAvatar({
    super.key,
    required this.driver,
    required this.radius,
    required this.fallback,
    this.backgroundColor = const Color(0xFFF3F6FB),
  });

  final MatchedDriver? driver;
  final double radius;
  final Widget fallback;
  final Color backgroundColor;

  @override
  State<DriverPhotoAvatar> createState() => _DriverPhotoAvatarState();
}

class _DriverPhotoAvatarState extends State<DriverPhotoAvatar> {
  Uint8List? _bytes;
  String? _path;

  /// The picture failed to decode: the fallback shows instead.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(DriverPhotoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driver?.photoUrl != widget.driver?.photoUrl) _follow();
  }

  void _follow() {
    final path = widget.driver?.photoUrl;
    _path = path;
    _failed = false;
    _bytes = DriverPhotos.cached(path);
    if (_bytes != null || !DriverPhotos.isTripPhotoPath(path)) return;
    DriverPhotos.load(path).then((bytes) {
      if (!mounted || _path != path || bytes == null) return;
      setState(() => _bytes = bytes);
    });
  }

  void _onImageError(Object error, StackTrace? stack) {
    final path = _path;
    if (_bytes != null) DriverPhotos.markBroken(path);
    AppLog.warning('driver_photo.undecodable', extra: {'error': '$error'});
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
      _bytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final asset = widget.driver?.photoAsset;
    final ImageProvider? image = _failed
        ? null
        : bytes != null
        ? MemoryImage(bytes)
        : asset != null
        ? AssetImage(asset)
        : null;
    return CircleAvatar(
      key: bytes != null ? const ValueKey('driver-photo-server') : null,
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      backgroundImage: image,
      // Live 5+5 test 2026-11-08: a photo that does not decode (staging test
      // drivers' placeholder file) is not a crash: the fallback shows.
      onBackgroundImageError: image == null ? null : _onImageError,
      child: image == null ? widget.fallback : null,
    );
  }
}
