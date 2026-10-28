import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/status_words.g.dart';
import 'package:movera_rider/features/support/application/support_ticket_repository.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.9.0 (owner, 2026-10-27): the rider's support tickets and
/// Movera's answers, read from movera-server.
class SupportTicketList extends StatefulWidget {
  const SupportTicketList({super.key, this.repository});

  final SupportTicketRepository? repository;

  @override
  State<SupportTicketList> createState() => _SupportTicketListState();
}

/// v0.10.4: the contract word for the ticket status (statusWords
/// ticketStatus); an unknown code reads as open.
String supportTicketStatus(AppLocalizations l, String status) =>
    statusWord(l, 'ticketStatus', status) ?? l.swTicketStatusOpen;

class _SupportTicketListState extends State<SupportTicketList> {
  late final SupportTicketRepository _repo =
      widget.repository ?? SupportTicketRepository();
  late Future<List<SupportTicketView>> _tickets = _repo.mine();

  void _reload() => setState(() => _tickets = _repo.mine());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return FutureBuilder<List<SupportTicketView>>(
      future: _tickets,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Column(
            key: const ValueKey('support-tickets-error'),
            children: [
              Text(l.supportTicketsFailed),
              TextButton(onPressed: _reload, child: Text(l.retry)),
            ],
          );
        }
        final tickets = snapshot.data ?? const <SupportTicketView>[];
        if (tickets.isEmpty) {
          return Text(
            l.supportTicketsEmpty,
            key: const ValueKey('support-tickets-empty'),
          );
        }
        return Column(
          key: const ValueKey('support-tickets'),
          children: [
            for (final ticket in tickets)
              Card(
                elevation: 0,
                child: ListTile(
                  key: ValueKey('support-ticket-${ticket.id}'),
                  title: Text(
                    ticket.subject,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(supportTicketStatus(l, ticket.status)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SupportTicketThread(
                        ticketId: ticket.id,
                        repository: _repo,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One ticket with every message, Movera's answers included.
class SupportTicketThread extends StatelessWidget {
  const SupportTicketThread({
    super.key,
    required this.ticketId,
    required this.repository,
  });

  final String ticketId;
  final SupportTicketRepository repository;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.supportMessagesTitle)),
      body: FutureBuilder<SupportTicketView>(
        future: repository.one(ticketId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final ticket = snapshot.data;
          if (snapshot.hasError || ticket == null) {
            return Center(child: Text(l.supportTicketsFailed));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                ticket.subject,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(supportTicketStatus(l, ticket.status)),
              const SizedBox(height: 16),
              for (final message in ticket.messages)
                Align(
                  key: ValueKey('support-ticket-message-${message.from}'),
                  alignment: message.fromSupport
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(
                      color: message.fromSupport
                          ? const Color(0xFFEFF5F9)
                          : const Color(0xFF0B2A3C),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.fromSupport)
                          Text(
                            message.adminName ?? l.supportTicketMovera,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          message.text,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: message.fromSupport
                                ? const Color(0xFF0B2A3C)
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
