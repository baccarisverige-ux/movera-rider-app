import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/mutation_attempt.dart';
import 'package:movera_rider/features/ride_complete/domain/ride_dispute_not_served.dart';

/// One message on a support ticket (contract v0.9.0 `TicketMessage`).
class SupportTicketMessage {
  const SupportTicketMessage({
    required this.from,
    required this.text,
    required this.at,
    this.adminName,
    this.supportName,
  });

  /// `rider` or `support`.
  final String from;
  final String text;
  final DateTime at;
  final String? adminName;

  /// v0.18.15 (owner QO-2 "Agent first name"): the answering admin's first
  /// name only; never an e-mail.
  final String? supportName;

  bool get fromSupport => from == 'support';

  static SupportTicketMessage fromJson(Map<String, dynamic> json) =>
      SupportTicketMessage(
        from: json['from']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime(0),
        adminName: json['adminName']?.toString(),
        supportName: json['supportName']?.toString(),
      );
}

/// A rider's own support ticket (contract v0.9.0 `SupportTicket`).
class SupportTicketView {
  const SupportTicketView({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.updatedAt,
    this.tripId,
    this.messages = const <SupportTicketMessage>[],
    this.feedback,
  });

  final String id;
  final String subject;
  final String category;

  /// `open`, `pending`, `resolved` or `closed`.
  final String status;
  final DateTime updatedAt;
  final String? tripId;
  final List<SupportTicketMessage> messages;

  /// v0.18.15 (owner "Not rating only comment suggestions"): the rider's
  /// optional comment after the ticket was solved.
  final String? feedback;

  static SupportTicketView fromJson(Map<String, dynamic> json) =>
      SupportTicketView(
        id: json['ticketId']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        status: json['status']?.toString() ?? 'open',
        updatedAt:
            DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime(0),
        tripId: json['tripId']?.toString(),
        feedback: (json['feedback'] as Map?)?['text']?.toString(),
        messages: [
          for (final item in (json['messages'] as List? ?? const []))
            if (item is Map)
              SupportTicketMessage.fromJson(Map<String, dynamic>.from(item)),
        ],
      );
}

/// v0.18.15 (contract.json#supportDesk, owner QO-4): the same seven topics as
/// the driver app; the server says which are on for the rider's country.
const supportTopics = <String>[
  'ride_dispute',
  'help',
  'lost_item',
  'payment',
  'account',
  'safety',
  'other',
];

/// Contract v0.9.0 §16 (owner, 2026-10-27): ride disputes and help requests
/// are support tickets (`POST /support/tickets`); Movera's answer comes back
/// on the ticket (`GET /support/tickets/{ticketId}`).
class SupportTicketRepository {
  SupportTicketRepository({ApiClient? api})
    : _api = api ?? AppScope.instance.api;

  final ApiClient _api;
  final MutationAttempt _mutation = MutationAttempt('support-ticket');

  /// Tickets are served by movera-server only (not by the demo transport).
  bool get available => _api.contractWire;

  /// The subject of a ticket: the first line of [text], at most 200 chars.
  static String subjectOf(String text, {required String fallback}) {
    final first = text.trim().split('\n').first.trim();
    final line = first.isEmpty ? fallback : first;
    return line.length <= 200 ? line : line.substring(0, 200);
  }

  /// Opens a ticket. [category] is from `contract.json#support.categories`.
  Future<SupportTicketView> open({
    String? tripId,
    required String category,
    required String subject,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) throw ArgumentError.value(text, 'text');
    if (!available) throw const RideDisputeNotServed();
    final intent = '${tripId ?? ''}|$category|$body';
    final answer = await _api.post(
      '/api/v1/support/tickets',
      body: {
        if (tripId != null && tripId.trim().isNotEmpty) 'tripId': tripId,
        'category': category,
        'subject': subject,
        'text': body,
      },
      idempotencyKey: _mutation.keyFor(intent),
    );
    _mutation.succeeded(intent);
    return SupportTicketView.fromJson(answer);
  }

  /// The rider's own tickets, newest change first.
  Future<List<SupportTicketView>> mine() async {
    if (!available) return const <SupportTicketView>[];
    final page = await _api.get('/api/v1/support/tickets?limit=50');
    return [
      for (final item in (page['items'] as List? ?? const []))
        if (item is Map)
          SupportTicketView.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  /// v0.18.15 (owner QO-1, chat-style): the rider writes again on the ticket;
  /// the answer is the ticket with every message.
  Future<SupportTicketView> write(String ticketId, String text) async {
    final body = text.trim();
    if (body.isEmpty) throw ArgumentError.value(text, 'text');
    final intent = 'msg|$ticketId|$body';
    final answer = await _api.post(
      '/api/v1/support/tickets/${Uri.encodeComponent(ticketId)}/messages',
      body: {'text': body},
      idempotencyKey: _mutation.keyFor(intent),
    );
    _mutation.succeeded(intent);
    return SupportTicketView.fromJson(answer);
  }

  /// v0.18.15: an optional comment once the ticket is solved (no stars).
  Future<SupportTicketView> comment(String ticketId, String text) async {
    final body = text.trim();
    if (body.isEmpty) throw ArgumentError.value(text, 'text');
    final intent = 'fb|$ticketId|$body';
    final answer = await _api.post(
      '/api/v1/support/tickets/${Uri.encodeComponent(ticketId)}/feedback',
      body: {'text': body},
      idempotencyKey: _mutation.keyFor(intent),
    );
    _mutation.succeeded(intent);
    return SupportTicketView.fromJson(answer);
  }

  /// v0.18.15: the topics that are on (contract order); all seven when the
  /// server is older, does not answer, or this is the demo transport.
  Future<List<String>> topics() async {
    if (!available) return supportTopics;
    try {
      final answer = await _api.get('/api/v1/support/topics');
      final on = [
        for (final item in (answer['topics'] as List? ?? const []))
          if (supportTopics.contains(item)) item.toString(),
      ];
      return on.isEmpty ? supportTopics : on;
    } catch (_) {
      return supportTopics;
    }
  }

  /// One ticket with its messages (Movera's answers included).
  Future<SupportTicketView> one(String ticketId) async {
    final json = await _api.get(
      '/api/v1/support/tickets/${Uri.encodeComponent(ticketId)}',
    );
    return SupportTicketView.fromJson(json);
  }
}
