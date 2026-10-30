import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../data/backend/message_backend.dart' show ConversationBlock;
import '../models/models.dart';
import '../providers/core_providers.dart';
import '../providers/message_providers.dart';
import '../services/file_service.dart';
import 'common.dart';
import 'document_viewer.dart';
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
    this.templates = const {},
  });

  final String applicationId;
  final bool asEmployer;

  /// The company (for candidates) or the candidate (for employers).
  final String otherName;

  /// A message sent before threads existed; shown first.
  final String? legacyEmployerMessage;
  final ValueChanged<String>? onSent;
  final bool enabled;

  /// Ready-made messages (label -> text) the writer can start from.
  final Map<String, String> templates;

  @override
  ConsumerState<MessageThread> createState() => _MessageThreadState();
}

class _MessageThreadState extends ConsumerState<MessageThread> {
  final _text = TextEditingController();
  bool _sending = false;
  PickedFile? _file;

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

  Future<void> _pickPdf() async {
    try {
      final f = await ref.read(fileServiceProvider).pickDocument();
      if (f != null) setState(() => _file = f);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    final file = _file;
    if (body.isEmpty && file == null) return;
    setState(() => _sending = true);
    try {
      final backend = ref.read(messageBackendProvider);
      final attachment = file == null ? null : await backend.uploadAttachment(file.name, file.bytes);
      final sent = await backend.send(widget.applicationId, body, asEmployer: widget.asEmployer, attachment: attachment);
      _text.clear();
      setState(() => _file = null);
      ref.invalidate(messageThreadProvider(widget.applicationId));
      widget.onSent?.call(sent.body);
      if (mounted) showSnack(context, file == null ? 'Message sent' : 'Message and ${file.name} sent');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report() async {
    final r = await showDialog<(String, String)>(context: context, builder: (_) => _ReportConversationDialog(otherName: widget.otherName));
    if (r == null) return;
    try {
      await ref.read(messageBackendProvider).report(widget.applicationId, r.$1, r.$2);
      if (mounted) showSnack(context, 'Thanks. Our team will review your report.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _setBlocked(bool block) async {
    if (block) {
      final ok = await confirmDialog(
        context,
        title: 'Block ${widget.otherName}?',
        message: widget.asEmployer
            ? 'Neither of you will be able to send messages on any of their applications to your company. You can unblock them later.'
            : 'Neither of you will be able to send messages on any of your applications to ${widget.otherName}. You can unblock them later.',
        confirmLabel: 'Block',
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      await ref.read(messageBackendProvider).setBlocked(widget.applicationId, block);
      ref.invalidate(conversationBlockProvider(widget.applicationId));
      if (mounted) showSnack(context, block ? '${widget.otherName} is blocked.' : '${widget.otherName} is unblocked.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(messageThreadProvider(widget.applicationId));
    final block = ref.watch(conversationBlockProvider(widget.applicationId)).value ?? const ConversationBlock();
    final messages = async.value ?? const <AppMessage>[];
    final legacy = widget.legacyEmployerMessage;
    final showLegacy = legacy != null && legacy.isNotEmpty && !messages.any((m) => m.fromEmployer && m.body == legacy);
    final employerHasWritten = showLegacy || messages.any((m) => m.fromEmployer) || (legacy?.isNotEmpty ?? false);
    final canWrite = widget.enabled && !block.blocked && (widget.asEmployer || employerHasWritten);
    final muted = context.palette.muted;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerRight,
        child: PopupMenuButton<String>(
          tooltip: 'Report or block',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (v) => v == 'report' ? _report() : _setBlocked(v == 'block'),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'report',
              child: ListTile(leading: const Icon(Icons.flag_outlined), title: Text('Report ${widget.otherName}'), contentPadding: EdgeInsets.zero),
            ),
            PopupMenuItem(
              value: block.byMe ? 'unblock' : 'block',
              child: ListTile(
                leading: Icon(block.byMe ? Icons.lock_open_rounded : Icons.block_rounded),
                title: Text(block.byMe ? 'Unblock ${widget.otherName}' : 'Block ${widget.otherName}'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
      if (block.blocked)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.block_rounded, color: muted, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                block.byMe ? 'You blocked ${widget.otherName}. Messages are off.' : 'Messages are off for this conversation.',
                style: context.text.bodyMedium,
              ),
            ),
          ]),
        ),
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
          body: m.hasAttachment && m.body == 'Sent a document: ${m.attachmentName}' ? '' : m.body,
          mine: m.fromEmployer == widget.asEmployer,
          label: m.fromEmployer == widget.asEmployer ? 'You' : widget.otherName,
          at: m.createdAt,
          attachment: !m.hasAttachment
              ? null
              : _AttachmentTile(
                  name: m.attachmentName!,
                  onOpen: () => viewDocument(
                    context,
                    title: m.attachmentName!,
                    fileName: m.attachmentName!,
                    format: DocumentFormat.pdf,
                    storagePath: m.attachmentPath,
                    loadUrl: ref.read(messageBackendProvider).attachmentUrl,
                  ),
                ),
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
        if (_file != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InputChip(
              avatar: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.danger, size: 18),
              label: Text('${_file!.name} · ${(_file!.size / 1024).ceil()} KB', overflow: TextOverflow.ellipsis),
              onDeleted: _sending ? null : () => setState(() => _file = null),
              deleteButtonTooltipMessage: 'Remove file',
            ),
          ),
        Row(children: [
          IconButton(
            tooltip: widget.asEmployer ? 'Attach a PDF (offer letter, contract...)' : 'Attach a PDF',
            onPressed: _sending ? null : _pickPdf,
            icon: Icon(Icons.attach_file_rounded, color: context.colors.primary),
          ),
          if (widget.templates.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Use a template',
              onSelected: (t) => setState(() => _text.text = t),
              itemBuilder: (_) => [for (final e in widget.templates.entries) PopupMenuItem(value: e.value, child: Text(e.key))],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.text_snippet_outlined, size: 18, color: context.colors.primary),
                  const SizedBox(width: 6),
                  Text('Template', style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
                ]),
              ),
            ),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(widget.asEmployer ? 'Send message' : 'Send reply'),
          ),
        ]),
      ] else if (widget.enabled && !block.blocked && !widget.asEmployer && messages.isNotEmpty)
        Text('You can reply once the employer has written to you.', style: context.text.bodySmall?.copyWith(color: muted)),
    ]);
  }
}

const _conversationReportReasons = [
  'Asked me to pay money',
  'Harassment or abusive language',
  'Spam or scam',
  'Inappropriate or offensive content',
  'Something else',
];

class _ReportConversationDialog extends StatefulWidget {
  const _ReportConversationDialog({required this.otherName});
  final String otherName;

  @override
  State<_ReportConversationDialog> createState() => _ReportConversationDialogState();
}

class _ReportConversationDialogState extends State<_ReportConversationDialog> {
  String? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Report ${widget.otherName}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Our team reads every report and can see these messages. You can also block them from the same menu.'),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                child: Column(children: [
                  for (final r in _conversationReportReasons) RadioListTile<String>(contentPadding: EdgeInsets.zero, dense: true, value: r, title: Text(r)),
                ]),
              ),
              TextField(controller: _details, minLines: 2, maxLines: 4, maxLength: 500, decoration: const InputDecoration(labelText: 'Details (optional)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _reason == null ? null : () => Navigator.pop(context, (_reason!, _details.text.trim())),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Send report'),
          ),
        ],
      );
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.name, required this.onOpen});
  final String name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            decoration: BoxDecoration(border: Border.all(color: context.palette.border), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.picture_as_pdf_outlined, color: AppColors.danger),
              const SizedBox(width: 8),
              Flexible(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
              const SizedBox(width: 8),
              Text('Open', style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
            ]),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.body, required this.mine, required this.label, required this.at, this.attachment});
  final String body;
  final bool mine;
  final String label;
  final DateTime? at;
  final Widget? attachment;

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
            if (body.isNotEmpty) SelectableText(body, style: context.text.bodyMedium),
            if (attachment != null) ...[
              if (body.isNotEmpty) const SizedBox(height: 8),
              attachment!,
            ],
          ]),
        ),
      ),
    );
  }
}
