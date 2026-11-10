part of 'waiting_for_driver.dart';

/// v0.18.56 §78 on the trip screen: the chat is read once and then follows
/// the trip stream (no 3 s / 10 s polls); a new message from the driver or
/// Support opens a folded sheet (owner Q82, `sheetAutoOpen: new_message`).
extension _WaitingTripChat on _WaitingForDriverState {
  void _startTripChat(String rideId, TripMessagesTransport transport) {
    final chat = MessagesController.forRide(rideId, transport: transport);
    _messages = chat;
    _seenUnread = chat.unreadCount;
    chat.addListener(_onTripChatChanged);
    unawaited(chat.refresh());
    unawaited(chat.loadOptions());
  }

  void _onTripChatChanged() {
    final chat = _messages;
    if (chat == null || !mounted) return;
    final unread = chat.unreadCount;
    final grew = unread > _seenUnread;
    _seenUnread = unread;
    if (grew && chat.options.opensSheetOnNewMessage) _openFoldedSheet();
  }

  /// Only a folded sheet (below its resting stop) opens; a sheet the rider
  /// holds open or full stays where it is.
  void _openFoldedSheet() {
    if (!_sheetController.hasClient) return;
    final media = MediaQuery.of(context);
    final resting = _minSheet(media);
    final offset = _sheetController.metrics?.offset;
    if (offset == null || offset >= resting - 1) return;
    _sheetController.animateTo(
      SheetOffset.absolute(resting),
      duration: MoveraDurations.normal,
      curve: Curves.easeOutCubic,
    );
  }
}
