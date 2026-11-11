/// Contract v0.18.64 §85 (owner 2026-11-11: "the language must arrive with
/// the receiver language and the translate when click on it must open
/// original language"): the translations of one trip's chat, kept with the
/// ride's conversation ([MessagesRepository]) while the trip is open, in
/// memory only (never stored, cleared at the trip's end).
///
/// A message from the driver (or support) shows translated into the rider's
/// own app language once its translation is here; "See original" shows the
/// text as written ([showOriginal]) and a second tap the translation again
/// ([showTranslation]), with no new request.
library;

class ChatTranslations {
  final Map<String, String> _text = {};
  final Set<String> _original = {};
  final Set<String> _busy = {};
  final Set<String> _autoTried = {};
  bool _autoStopped = false;

  /// The text to show for message [id] written as [original].
  String shown(String id, String original) =>
      showsTranslation(id) ? _text[id]! : original;

  /// The translation of [id] shows now.
  bool showsTranslation(String id) =>
      _text.containsKey(id) && !_original.contains(id);

  /// A translation of [id] is here (shown or not).
  bool has(String id) => _text.containsKey(id);

  /// A request for [id] is on its way.
  bool busy(String id) => _busy.contains(id);

  /// The app's own request for [id] was made (once per message).
  bool autoTried(String id) => _autoTried.contains(id);

  /// After `coming_soon`, `translation_off` or `auto_translate_off` the app
  /// stops asking by itself for this trip (no request per message).
  bool get autoStopped => _autoStopped;

  void stopAuto() => _autoStopped = true;

  void markAutoTried(String id) => _autoTried.add(id);

  /// False when [id] is already on its way.
  bool start(String id) => _busy.add(id);

  void done(String id, String? text) {
    _busy.remove(id);
    if (text != null) {
      _text[id] = text;
      _original.remove(id);
    }
  }

  void showOriginal(String id) => _original.add(id);

  void showTranslation(String id) => _original.remove(id);

  /// The trip ended (contract v0.18.5 `chat.appStorage`): nothing is kept.
  void clear() {
    _text.clear();
    _original.clear();
    _busy.clear();
    _autoTried.clear();
    _autoStopped = false;
  }
}
