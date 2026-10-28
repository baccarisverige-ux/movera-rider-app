import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/ride_complete/domain/ride_dispute_not_served.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/features/support/application/support_ticket_repository.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/support/presentation/support_tickets.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.9.0 §16 (owner, 2026-10-27): help requests are support
/// tickets, and the rider reads Movera's answer in the app.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );
  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  final ticket = {
    'ticketId': 'tkt_1',
    'subject': 'Lost my umbrella',
    'category': 'help',
    'status': 'pending',
    'updatedAt': '2026-10-27T10:00:00Z',
  };
  final thread = {
    ...ticket,
    'messages': [
      {
        'messageId': 'm1',
        'from': 'rider',
        'text': 'Lost my umbrella',
        'at': '2026-10-27T09:00:00Z',
      },
      {
        'messageId': 'm2',
        'from': 'support',
        'text': 'We found it, call us.',
        'at': '2026-10-27T10:00:00Z',
        'adminName': 'Nora Lind',
      },
    ],
  };

  ({SupportTicketRepository repo, List<String> calls, List<Object?> bodies})
  server() {
    final calls = <String>[];
    final bodies = <Object?>[];
    final api = ApiClient(
      env: staging,
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          bodies.add(jsonDecode(request.body));
          return http.Response(jsonEncode(ticket), 201);
        }
        if (request.url.path.endsWith('/tkt_1')) {
          return http.Response(jsonEncode(thread), 200);
        }
        return http.Response(
          jsonEncode({
            'items': [ticket],
            'nextCursor': null,
          }),
          200,
        );
      }),
    );
    return (
      repo: SupportTicketRepository(api: api),
      calls: calls,
      bodies: bodies,
    );
  }

  test('a help request is POST /support/tickets with the first line as the '
      'subject; the list and one ticket are read back', () async {
    final s = server();
    await s.repo.open(
      category: 'help',
      subject: SupportTicketRepository.subjectOf(
        'Lost my umbrella\nIn the back seat',
        fallback: 'Help',
      ),
      text: 'Lost my umbrella\nIn the back seat',
    );
    expect(s.bodies.single, {
      'category': 'help',
      'subject': 'Lost my umbrella',
      'text': 'Lost my umbrella\nIn the back seat',
    });
    final mine = await s.repo.mine();
    expect(mine.single.status, 'pending');
    final one = await s.repo.one('tkt_1');
    expect(one.messages.last.fromSupport, isTrue);
    expect(one.messages.last.adminName, 'Nora Lind');
    expect(s.calls, [
      'POST /api/v1/support/tickets',
      'GET /api/v1/support/tickets',
      'GET /api/v1/support/tickets/tkt_1',
    ]);
    expect(
      SupportTicketRepository.subjectOf('x' * 300, fallback: 'Help').length,
      200,
    );
  });

  test('the demo transport has no tickets: nothing is sent', () async {
    final calls = <String>[];
    final repo = SupportTicketRepository(
      api: ApiClient(
        env: demo,
        client: MockClient((request) async {
          calls.add(request.url.path);
          return http.Response('{}', 404);
        }),
      ),
    );
    expect(repo.available, isFalse);
    await expectLater(
      repo.open(category: 'help', subject: 'x', text: 'x'),
      throwsA(isA<RideDisputeNotServed>()),
    );
    expect(await repo.mine(), isEmpty);
    expect(calls, isEmpty);
  });

  testWidgets('Help without a ride sends a help request and says it was sent', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SupportChat(
          contact: const SupportContact(email: ''),
          sendHelp: ({required text}) async => sent.add(text),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('support-message-field')),
      'The app logged me out',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();
    expect(sent, ['The app logged me out']);
    expect(find.byKey(const ValueKey('support-message-sent')), findsOneWidget);
  });

  testWidgets('Support messages lists the tickets and shows Movera\'s answer', (
    tester,
  ) async {
    L10n.use('sv');
    addTearDown(() => L10n.use('en'));
    final s = server();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupportTicketList(repository: s.repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lost my umbrella'), findsOneWidget);
    // v0.10.4: the contract ticketStatus word for pending.
    expect(find.text('Väntande'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('support-ticket-tkt_1')));
    await tester.pumpAndSettle();
    expect(find.text('We found it, call us.'), findsOneWidget);
    expect(find.text('Nora Lind'), findsOneWidget);
  });
}
