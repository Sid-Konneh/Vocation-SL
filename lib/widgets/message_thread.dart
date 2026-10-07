import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/models.dart';
import '../providers/message_providers.dart';
import 'common.dart';
import 'skeletons.dart';

/// The employer ⇄ candidate conversation on an application, with a reply box.
/// Candidates can reply once the employer has written to them.
class MessageThread extends ConsumerStatefulWidget {
  const MessageThread({
    super.key,
    required this.applicationId,
    required this.asEmployer,
    required this.otherName,
    this.legacyEmployerMessage,
    this.onSent,
    this.enabled = true,
  });

  final String applicationId;
  final bool asEmployer;

  /// The company (for candidates) or the candidate (for employers).
  final String otherName;

  /// A message sent before threads existed; shown first.
  final String? legacyEmployerMessage;
  final ValueChanged<String>? onSent;
  final bool enabled;

  @override
  ConsumerState<MessageThread> createState() => _MessageThreadState();
}

class _MessageThreadState extends ConsumerState<MessageThread> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    await ref.read(messageBackendProvider).markRead(widget.applicationId);
    if (widget.asEmployer && mounted) ref.invalidate(unreadRepliesProvider);
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(messageBackendProvider).send(widget.applicationId, body, asEmployer: widget.asEmployer);
      _text.clear();
      ref.invalidate(messageThreadProvider(widget.applicationId));
      widget.onSent?.call(body);
      if (mounted) showSnack(context, 'Message sent');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(messageThreadProvider(widget.applicationId));
    final messages = async.value ?? const <AppMessage>[];
    final legacy = widget.legacyEmployerMessage;
    final showLegacy = legacy != null && legacy.isNotEmpty && !messages.any((m) => m.fromEmployer && m.body == legacy);
    final employerHasWritten = showLegacy || messages.any((m) => m.fromEmployer) || (legacy?.isNotEmpty ?? false);
    final canWrite = widget.enabled && (widget.asEmployer || employerHasWritten);
    final muted = context.palette.muted;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (async.isLoading && !async.hasValue) const MessageThreadSkeleton(),
      if (async.hasError && !async.hasValue)
        Text('Couldn\'t load messages. Pull to refresh.', style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
      if (!showLegacy && messages.isEmpty && async.hasValue)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            widget.asEmployer
                ? 'No messages yet. Write to ${widget.otherName}; they can reply here.'
                : 'No messages yet. If ${widget.otherName} contacts you, you can reply here.',
            style: context.text.bodyMedium?.copyWith(color: muted),
          ),
        ),
      if (showLegacy) _Bubble(body: legacy, mine: widget.asEmployer, label: widget.asEmployer ? 'You' : widget.otherName, at: null),
      for (final m in messages)
        _Bubble(
          body: m.body,
          mine: m.fromEmployer == widget.asEmployer,
          label: m.fromEmployer == widget.asEmployer ? 'You' : widget.otherName,
          at: m.createdAt,
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            ref.invalidate(messageThreadProvider(widget.applicationId));
            _markRead();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Check for new messages'),
        ),
      ),
      if (canWrite) ...[
        TextField(
          controller: _text,
          minLines: 1,
          maxLines: 6,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: widget.asEmployer ? 'Message to ${widget.otherName}' : 'Reply to ${widget.otherName}',
            hintText: widget.asEmployer ? 'They\'ll get a notification in the app.' : 'Write your reply',
            alignLabelWithHint: true,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(widget.asEmployer ? 'Send message' : 'Send reply'),
          ),
        ),
      ] else if (widget.enabled && !widget.asEmployer && messages.isNotEmpty)
        Text('You can reply once the employer has written to you.', style: context.text.bodySmall?.copyWith(color: muted)),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.body, required this.mine, required this.label, required this.at});
  final String body;
  final bool mine;
  final String label;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final bg = mine ? context.colors.primaryContainer : context.palette.surface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: bg,
            border: mine ? null : Border.all(color: context.palette.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(at == null ? label : '$label · ${Fmt.ago(at!)}',
                style: context.text.labelSmall?.copyWith(color: context.palette.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText(body, style: context.text.bodyMedium),
          ]),
        ),
      ),
    );
  }
}
