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

/// v0.18.15 (owner QO-2 "Agent first name"): "`<first name>` · Movera
/// Support", or "Movera Support" without a name; never an e-mail.
String supportSenderLine(AppLocalizations l, SupportTicketMessage message) {
  final name = message.supportName?.trim();
  return name == null || name.isEmpty || name.contains('@')
      ? l.supportMovera
      : l.supportAgentLine(name);
}

/// One ticket as a chat (owner QO-1): Movera's answers and the rider's
/// messages, and a box to write again while the ticket is not closed.
class SupportTicketThread extends StatefulWidget {
  const SupportTicketThread({
    super.key,
    required this.ticketId,
    required this.repository,
  });

  final String ticketId;
  final SupportTicketRepository repository;

  @override
  State<SupportTicketThread> createState() => _SupportTicketThreadState();
}

class _SupportTicketThreadState extends State<SupportTicketThread> {
  late Future<SupportTicketView> _ticket = widget.repository.one(
    widget.ticketId,
  );
  final _reply = TextEditingController();
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      final next = await widget.repository.write(widget.ticketId, text);
      _reply.clear();
      if (!mounted) return;
      setState(() {
        _ticket = Future.value(next);
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.supportMessagesTitle)),
      body: FutureBuilder<SupportTicketView>(
        future: _ticket,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final ticket = snapshot.data;
          if (snapshot.hasError || ticket == null) {
            return Center(child: Text(l.supportTicketsFailed));
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
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
                                  supportSenderLine(l, message),
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
                ),
              ),
              if (ticket.status == 'closed')
                Padding(
                  key: const ValueKey('support-ticket-closed'),
                  padding: const EdgeInsets.all(16),
                  child: Text(l.supportTicketClosedNote),
                )
              else
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_failed)
                          Text(
                            l.supportReplyFailed,
                            style: const TextStyle(color: Colors.red),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('support-ticket-reply'),
                                controller: _reply,
                                maxLength: 5000,
                                minLines: 1,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: l.supportReplyHint,
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              key: const ValueKey('support-ticket-reply-send'),
                              onPressed: _sending ? null : _send,
                              child: Text(l.supportReplySend),
                            ),
                          ],
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
