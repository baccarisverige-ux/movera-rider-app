import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens another app with [uri] (the SMS app); false when none took it.
typedef ShareTripLauncher = Future<bool> Function(Uri uri);

/// Hands [text] to the phone's own share sheet.
typedef ShareTripSharer = Future<void> Function(String text);

/// BQ-S10 (contract v0.18.116 `contract.json#shareTrip`): how the rider's
/// phone sends the trip's live link. The server sends nothing to a contact;
/// the phone's SMS app or its share sheet does, after the rider's tap.
abstract final class ShareTripActions {
  /// Replaced in tests; [reset] puts the phone's own back.
  static ShareTripLauncher launcher = _launch;
  static ShareTripSharer sharer = _share;

  static void reset() {
    launcher = _launch;
    sharer = _share;
  }

  static Future<bool> _launch(Uri uri) => launchUrl(uri);

  static Future<void> _share(String text) =>
      SharePlus.instance.share(ShareParams(text: text));

  /// `sms:<number>?body=<text>`: the SMS app, ready to send to one contact.
  static Uri smsUri(String phoneE164, String text) => Uri.parse(
    'sms:${phoneE164.replaceAll(RegExp(r'[^0-9+]'), '')}'
    '?body=${Uri.encodeComponent(text)}',
  );

  /// Opens the SMS app for [phoneE164] with [text]; where no SMS app takes
  /// it (the web, a tablet) the phone's share sheet opens instead.
  static Future<void> sendSms(String phoneE164, String text) async {
    final opened = await launcher(
      smsUri(phoneE164, text),
    ).catchError((Object _) => false);
    if (!opened) await sharer(text);
  }
}
