import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/backend/hiring_backend.dart';
import '../../models/models.dart';
import '../../providers/hiring_providers.dart';
import '../../providers/session_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

Color supportStatusColor(SupportStatus s) => switch (s) {
      SupportStatus.open => AppColors.warning,
      SupportStatus.answered => AppColors.green,
      SupportStatus.closed => const Color(0xFF6B7280),
    };

class SupportStatusChip extends StatelessWidget {
  const SupportStatusChip(this.status, {super.key, this.staffView = false});
  final SupportStatus status;

  /// Admins read "open" as "needs a reply".
  final bool staffView;

  @override
  Widget build(BuildContext context) {
    final c = supportStatusColor(status);
    final label = staffView && status == SupportStatus.open ? 'Needs a reply' : status.label;
    return TagChip(label, dense: true, color: c, background: c.withValues(alpha: 0.12));
  }
}

/// The signed-in user's support requests.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myTicketsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/support/new'),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New request'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myTicketsProvider),
        child: ResponsiveCenter(
          maxWidth: AppSpacing.maxReadingWidth,
          child: async.when(
            loading: () => const Skeleton(child: Column(children: [ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true)])),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(myTicketsProvider)),
            data: (tickets) => tickets.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 40),
                    EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'How can we help?',
                      message: 'Ask a question or report a problem, including a suspicious job. The Vocation SL team replies here, '
                          'and you\'ll get a notification.',
                      action: 'New request',
                      onAction: () => context.push('/support/new'),
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 96),
                    itemCount: tickets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final t = tickets[i];
                      return Card(
                        child: ListTile(
                          onTap: () => context.push('/support/${t.id}'),
                          title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${t.category.label} · ${Fmt.ago(t.lastMessageAt)}'),
                          trailing: SupportStatusChip(t.status),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class NewSupportRequestScreen extends ConsumerStatefulWidget {
  const NewSupportRequestScreen({super.key});

  @override
  ConsumerState<NewSupportRequestScreen> createState() => _NewSupportRequestScreenState();
}

class _NewSupportRequestScreenState extends ConsumerState<NewSupportRequestScreen> {
  SupportCategory? _category;
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final problem = _category == null
        ? 'Choose what it\'s about.'
        : _subject.text.trim().length < 3
            ? 'Add a short subject.'
            : _body.text.trim().length < 10
                ? 'Tell us a little more (at least 10 characters).'
                : null;
    if (problem != null) {
      showSnack(context, problem, error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      final id = await ref.read(hiringBackendProvider).openTicket(
            subject: _subject.text,
            category: _category!,
            body: _body.text,
            side: ref.read(roleProvider) ?? UserRole.seeker,
          );
      ref.invalidate(myTicketsProvider);
      if (!mounted) return;
      showSnack(context, 'Sent. We\'ll reply here and send you a notification.');
      context.pushReplacement('/support/$id');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New request')),
        body: ResponsiveCenter(
          maxWidth: AppSpacing.maxReadingWidth,
          child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
            DropdownButtonFormField<SupportCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'What is it about?'),
              items: [for (final c in SupportCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (v) => setState(() => _category = v),
            ),
            if (_category == SupportCategory.scam) ...[
              const SizedBox(height: 8),
              Text('Include the job title and company. Never pay anyone to get a job.',
                  style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
            ],
            const SizedBox(height: 12),
            TextField(controller: _subject, maxLength: 150, decoration: const InputDecoration(labelText: 'Subject')),
            TextField(
              controller: _body,
              minLines: 5,
              maxLines: 12,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Details', hintText: 'What happened, and what did you expect?', alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            Text('Don\'t include passwords or Mobile Money PINs. The team will never ask for them.',
                style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: const Text('Send'),
            ),
          ]),
        ),
      );
}

/// One support request and its replies. [staff] is the admin view.
class SupportThreadScreen extends ConsumerStatefulWidget {
  const SupportThreadScreen({super.key, required this.ticketId, this.staff = false, this.ticket});
  final String ticketId;
  final bool staff;
  final SupportTicket? ticket;

  @override
  ConsumerState<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends ConsumerState<SupportThreadScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(supportThreadProvider(widget.ticketId));
    ref.invalidate(myTicketsProvider);
    ref.invalidate(allTicketsProvider);
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final backend = ref.read(hiringBackendProvider);
      if (backend is DemoHiringBackend) backend.replyAsStaff = widget.staff;
      await backend.replySupport(widget.ticketId, text);
      _reply.clear();
      _refresh();
      if (mounted) showSnack(context, widget.staff ? 'Reply sent. They\'ll get a notification.' : 'Sent');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(SupportStatus s) async {
    try {
      await ref.read(hiringBackendProvider).setSupportStatus(widget.ticketId, s);
      _refresh();
      if (mounted) showSnack(context, s == SupportStatus.closed ? 'Request closed' : 'Request reopened');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tickets = (widget.staff ? ref.watch(allTicketsProvider) : ref.watch(myTicketsProvider)).value ?? const <SupportTicket>[];
    final t = tickets.where((x) => x.id == widget.ticketId).firstOrNull ?? widget.ticket;
    final thread = ref.watch(supportThreadProvider(widget.ticketId));
    final closed = t?.status == SupportStatus.closed;

    return Scaffold(
      appBar: AppBar(
        title: Text(t?.subject ?? 'Support request', overflow: TextOverflow.ellipsis),
        actions: [
          if (t != null)
            TextButton(
              onPressed: () => _setStatus(closed ? SupportStatus.open : SupportStatus.closed),
              child: Text(closed ? 'Reopen' : (widget.staff ? 'Close' : 'Mark solved')),
            ),
        ],
      ),
      body: ResponsiveCenter(
        maxWidth: AppSpacing.maxReadingWidth,
        child: Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
                if (t != null) ...[
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SupportStatusChip(t.status, staffView: widget.staff),
                    TagChip(t.category.label, dense: true),
                    if (widget.staff) TagChip(t.side == UserRole.employer ? 'Employer' : 'Job seeker', dense: true),
                  ]),
                  if (widget.staff && (t.userName.isNotEmpty || t.userEmail.isNotEmpty)) ...[
                    const SizedBox(height: 8),
                    SelectableText([t.userName, t.userEmail].where((s) => s.isNotEmpty).join(' · '), style: context.text.bodyMedium),
                  ],
                  const SizedBox(height: 16),
                ],
                ...thread.when(
                  loading: () => [const Skeleton(child: Column(children: [ListTileSkeleton(), ListTileSkeleton()]))],
                  error: (e, _) => [ErrorState(error: e, onRetry: _refresh)],
                  data: (messages) => [
                    for (final m in messages)
                      _Bubble(
                        body: m.body,
                        at: m.createdAt,
                        mine: m.fromStaff == widget.staff,
                        label: m.fromStaff ? 'Vocation SL support' : (widget.staff ? (t?.userName.isNotEmpty ?? false ? t!.userName : 'User') : 'You'),
                      ),
                  ],
                ),
              ]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: closed ? 'Write to reopen this request' : (widget.staff ? 'Reply as Vocation SL support' : 'Write a reply'),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.body, required this.at, required this.mine, required this.label});
  final String body;
  final DateTime at;
  final bool mine;
  final String label;

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: mine ? context.colors.primaryContainer : context.palette.surface,
              border: mine ? null : Border.all(color: context.palette.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label · ${Fmt.ago(at)}', style: context.text.labelSmall?.copyWith(color: context.palette.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              SelectableText(body, style: context.text.bodyMedium),
            ]),
          ),
        ),
      );
}
