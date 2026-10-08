import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/invoice_pdf.dart';
import '../../widgets/states.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

final _money = NumberFormat('#,##0.00');
String money(double v, [String currency = 'SLE']) => '$currency ${_money.format(v)}';

/// A filter on the invoice list. [needsPricing] and [overdue] are views
/// across statuses; the rest match a status.
enum _View {
  all('All'),
  needsPricing('Needs pricing'),
  draft('Draft'),
  issued('Issued'),
  overdue('Overdue'),
  paid('Paid'),
  voided('Void');

  const _View(this.label);
  final String label;

  bool matches(Invoice i, DateTime now) => switch (this) {
        all => true,
        needsPricing => i.needsPricing,
        draft => i.status == InvoiceStatus.draft,
        issued => i.status == InvoiceStatus.issued,
        overdue => i.isOverdueAt(now),
        paid => i.status == InvoiceStatus.paid,
        voided => i.status == InvoiceStatus.voided,
      };
}

class AdminInvoicesScreen extends ConsumerStatefulWidget {
  const AdminInvoicesScreen({super.key});

  @override
  ConsumerState<AdminInvoicesScreen> createState() => _AdminInvoicesScreenState();
}

class _AdminInvoicesScreenState extends ConsumerState<AdminInvoicesScreen> {
  _View _view = _View.all;
  String _q = '';

  Future<void> _open(Invoice inv) => showDialog<void>(
        context: context,
        builder: (_) => InvoiceEditor(invoice: inv),
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminInvoicesProvider);
    final now = DateTime.now();
    return EmployerPage(
      title: 'Invoices',
      subtitle: 'A draft invoice is created for every job when it goes live. Enter the cost, issue it, then record the payment.',
      onRefresh: () async => ref.invalidate(adminInvoicesProvider),
      children: [
        AdminAsync<List<Invoice>>(
          value: async,
          onRetry: () => ref.invalidate(adminInvoicesProvider),
          builder: (all) {
            final live = all.where((i) => i.status != InvoiceStatus.voided);
            double sum(Iterable<Invoice> l) => l.fold(0, (s, i) => s + i.total);
            final outstanding = live.where((i) => i.status == InvoiceStatus.issued);
            final overdue = all.where((i) => i.isOverdueAt(now));
            final paid = all.where((i) => i.status == InvoiceStatus.paid);
            final paidThisMonth = paid.where((i) => i.paidAt != null && i.paidAt!.year == now.year && i.paidAt!.month == now.month);
            final toPrice = all.where((i) => i.needsPricing).length;

            final q = _q.trim().toLowerCase();
            final list = all
                .where((i) => _view.matches(i, now) &&
                    (q.isEmpty || '${i.number} ${i.jobTitle} ${i.billToName} ${i.billToEmail} ${i.paymentReference}'.toLowerCase().contains(q)))
                .toList();

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatGrid(children: [
                StatTile(
                  label: 'Needs pricing',
                  value: '$toPrice',
                  detail: 'Drafts with no cost yet',
                  icon: Icons.edit_note_rounded,
                  attention: toPrice > 0,
                  onTap: () => setState(() => _view = _View.needsPricing),
                ),
                StatTile(
                  label: 'Outstanding',
                  value: money(sum(outstanding)),
                  detail: '${outstanding.length} issued, unpaid',
                  icon: Icons.hourglass_bottom_rounded,
                  onTap: () => setState(() => _view = _View.issued),
                ),
                StatTile(
                  label: 'Overdue',
                  value: money(sum(overdue)),
                  detail: '${overdue.length} past due date',
                  icon: Icons.warning_amber_rounded,
                  attention: overdue.isNotEmpty,
                  onTap: () => setState(() => _view = _View.overdue),
                ),
                StatTile(
                  label: 'Paid this month',
                  value: money(sum(paidThisMonth)),
                  detail: '${money(sum(paid))} all time',
                  icon: Icons.payments_outlined,
                  onTap: () => setState(() => _view = _View.paid),
                ),
              ]),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final v in _View.values)
                  ChoiceChip(
                    label: Text('${v.label} (${all.where((i) => v.matches(i, now)).length})'),
                    selected: _view == v,
                    onSelected: (_) => setState(() => _view = v),
                  ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(hintText: 'Search number, job, company or reference', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              TableCard(
                empty: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: all.isEmpty ? 'No invoices yet' : 'No invoices match',
                  message: all.isEmpty ? 'An invoice is created automatically when a job is approved and goes live.' : 'Try another filter.',
                ),
                columns: const [
                  DataColumn(label: Text('Invoice')),
                  DataColumn(label: Text('Job')),
                  DataColumn(label: Text('Bill to')),
                  DataColumn(label: Text('Total'), numeric: true),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Issued')),
                  DataColumn(label: Text('Due')),
                  DataColumn(label: Text('PDF')),
                ],
                rows: [
                  for (final i in list)
                    DataRow(onSelectChanged: (_) => _open(i), cells: [
                      DataCell(Text(i.number, style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(i.jobTitle.isEmpty ? '—' : i.jobTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(i.billToName.isEmpty ? '—' : i.billToName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text(i.needsPricing ? 'Not priced' : money(i.total, i.currency),
                          style: i.needsPricing ? TextStyle(color: context.palette.muted) : null)),
                      DataCell(InvoiceStatusPill(i, now: now)),
                      DataCell(Text(i.issueDate == null ? '—' : Fmt.dateShort(i.issueDate!))),
                      DataCell(Text(i.dueDate == null ? '—' : Fmt.dateShort(i.dueDate!))),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'View PDF',
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InvoicePdfScreen(invoice: i))),
                        ),
                        IconButton(
                          tooltip: 'Download PDF',
                          icon: const Icon(Icons.download_rounded),
                          onPressed: () => downloadInvoicePdf(context, i),
                        ),
                      ])),
                    ]),
                ],
              ),
            ]);
          },
        ),
      ],
    );
  }
}

class InvoiceStatusPill extends StatelessWidget {
  const InvoiceStatusPill(this.invoice, {super.key, required this.now});
  final Invoice invoice;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final overdue = invoice.isOverdueAt(now);
    final (label, color) = overdue
        ? ('Overdue', AppColors.danger)
        : switch (invoice.status) {
            InvoiceStatus.draft => (invoice.needsPricing ? 'Needs pricing' : 'Draft', AppColors.warning),
            InvoiceStatus.issued => ('Issued', context.colors.primary),
            InvoiceStatus.paid => ('Paid', AppColors.success),
            InvoiceStatus.voided => ('Void', context.palette.muted),
          };
    return TagChip(label, dense: true, color: color, background: color.withValues(alpha: 0.12));
  }
}

/// View and edit one invoice. Read-only for moderators and viewers.
class InvoiceEditor extends ConsumerStatefulWidget {
  const InvoiceEditor({super.key, required this.invoice});
  final Invoice invoice;

  @override
  ConsumerState<InvoiceEditor> createState() => _InvoiceEditorState();
}

class _InvoiceEditorState extends ConsumerState<InvoiceEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.invoice.billToName);
  late final _email = TextEditingController(text: widget.invoice.billToEmail);
  late final _address = TextEditingController(text: widget.invoice.billToAddress);
  late final _description = TextEditingController(text: widget.invoice.description);
  late final _qty = TextEditingController(text: '${widget.invoice.quantity}');
  late final _price = TextEditingController(text: _num(widget.invoice.unitPrice));
  late final _discount = TextEditingController(text: _num(widget.invoice.discount));
  late final _tax = TextEditingController(text: _num(widget.invoice.taxRate));
  late final _method = TextEditingController(text: widget.invoice.paymentMethod);
  late final _reference = TextEditingController(text: widget.invoice.paymentReference);
  late final _notes = TextEditingController(text: widget.invoice.notes);
  late DateTime? _issueDate = widget.invoice.issueDate;
  late DateTime? _dueDate = widget.invoice.dueDate;
  bool _busy = false;

  static String _num(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));
  static double _parse(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  @override
  void dispose() {
    for (final c in [_name, _email, _address, _description, _qty, _price, _discount, _tax, _method, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Invoice _current({InvoiceStatus? status}) => widget.invoice.copyWith(
        billToName: _name.text.trim(),
        billToEmail: _email.text.trim(),
        billToAddress: _address.text.trim(),
        description: _description.text.trim(),
        quantity: int.tryParse(_qty.text.trim()) ?? 1,
        unitPrice: _parse(_price.text),
        discount: _parse(_discount.text),
        taxRate: _parse(_tax.text),
        issueDate: () => _issueDate,
        dueDate: () => _dueDate,
        paymentMethod: _method.text.trim(),
        paymentReference: _reference.text.trim(),
        notes: _notes.text.trim(),
        status: status,
      );

  Future<void> _save(InvoiceStatus status, String done) async {
    if (status != InvoiceStatus.voided && !(_form.currentState?.validate() ?? false)) return;
    final inv = _current(status: status);
    if (status != InvoiceStatus.draft && status != InvoiceStatus.voided && inv.unitPrice <= 0) {
      showSnack(context, 'Enter the cost before issuing the invoice.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminActionsProvider).run((b) => b.saveInvoice(inv), refresh: [adminInvoicesProvider]);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _void() async {
    if (!await confirmDialog(context,
        title: 'Void ${widget.invoice.number}?',
        message: 'The invoice is kept for your records but no longer counts as owed.',
        confirmLabel: 'Void invoice',
        destructive: true)) {
      return;
    }
    await _save(InvoiceStatus.voided, '${widget.invoice.number} voided');
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context,
        title: 'Delete ${widget.invoice.number}?',
        message: 'Only delete drafts created by mistake. Use Void for invoices that were sent.',
        confirmLabel: 'Delete',
        destructive: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminActionsProvider).run((b) => b.deleteInvoice(widget.invoice.id), refresh: [adminInvoicesProvider]);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Invoice deleted');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final text = invoiceText(_current(status: widget.invoice.status));
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: 'Invoice ${widget.invoice.number}'));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showSnack(context, 'Invoice copied');
    }
  }

  Future<void> _pickDate(bool issue) async {
    final initial = (issue ? _issueDate : _dueDate) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2100));
    if (d != null) setState(() => issue ? _issueDate = d : _dueDate = d);
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final canEdit = adminCan(ref, AdminRole.admin) && inv.status != InvoiceStatus.voided;
    final preview = _current();
    final muted = context.palette.muted;

    String? number(String? v, {bool required = false, double max = double.infinity}) {
      final s = (v ?? '').replaceAll(',', '').trim();
      if (s.isEmpty) return required ? 'Required' : null;
      final n = double.tryParse(s);
      if (n == null || n < 0) return 'Enter a number';
      if (n > max) return 'At most ${max.toStringAsFixed(0)}';
      return null;
    }

    Widget field(TextEditingController c, String label, {String? prefix, String? suffix, TextInputType? type, String? Function(String?)? validator, int lines = 1}) =>
        TextFormField(
          controller: c,
          enabled: canEdit,
          keyboardType: type,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          validator: validator,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, prefixText: prefix, suffixText: suffix),
        );

    Widget pair(Widget a, Widget b) => LayoutBuilder(
          builder: (context, c) => c.maxWidth < 420
              ? Column(children: [a, const SizedBox(height: 12), b])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]),
        );

    Widget dateButton(String label, DateTime? d, bool issue) => OutlinedButton.icon(
          onPressed: canEdit ? () => _pickDate(issue) : null,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text('$label: ${d == null ? (issue ? 'when issued' : '14 days after issue') : Fmt.date(d)}'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        );

    Widget totalRow(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: strong ? context.text.titleMedium : context.text.bodyMedium)),
            Text(value, style: (strong ? context.text.titleMedium : context.text.bodyMedium)?.copyWith(fontWeight: strong ? FontWeight.w800 : null)),
          ]),
        );

    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(inv.number)),
        InvoiceStatusPill(inv, now: DateTime.now()),
      ]),
      content: SizedBox(
        width: 640,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(inv.jobTitle.isEmpty ? 'Job no longer exists' : 'For job: ${inv.jobTitle}', style: context.text.titleSmall),
              Text('Created ${Fmt.date(inv.createdAt)}${inv.paidAt != null ? ' · Paid ${Fmt.date(inv.paidAt!)}' : ''}',
                  style: context.text.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: 16),
              Text('Bill to', style: context.text.labelLarge),
              const SizedBox(height: 8),
              field(_name, 'Company name', validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              pair(
                field(_email, 'Billing email', type: TextInputType.emailAddress,
                    validator: (v) => (v ?? '').trim().isEmpty || (v ?? '').contains('@') ? null : 'Enter a valid email'),
                field(_address, 'Address'),
              ),
              const SizedBox(height: 20),
              Text('Charges', style: context.text.labelLarge),
              const SizedBox(height: 8),
              field(_description, 'Description', validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              pair(
                field(_price, 'Cost (per item)', prefix: '${inv.currency} ', type: const TextInputType.numberWithOptions(decimal: true), validator: (v) => number(v)),
                field(_qty, 'Quantity', type: TextInputType.number, validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 1 ? 'At least 1' : null;
                }),
              ),
              const SizedBox(height: 12),
              pair(
                field(_discount, 'Discount', prefix: '${inv.currency} ', type: const TextInputType.numberWithOptions(decimal: true), validator: (v) => number(v)),
                field(_tax, 'GST / tax rate', suffix: '%', type: const TextInputType.numberWithOptions(decimal: true), validator: (v) => number(v, max: 100)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(AppSpacing.radius)),
                child: Column(children: [
                  totalRow('Subtotal', money(preview.subtotal, inv.currency)),
                  if (preview.discount > 0) totalRow('Discount', '− ${money(preview.discount, inv.currency)}'),
                  totalRow('Tax (${_num(preview.taxRate).isEmpty ? '0' : _num(preview.taxRate)}%)', money(preview.taxAmount, inv.currency)),
                  const Divider(),
                  totalRow('Total', money(preview.total, inv.currency), strong: true),
                ]),
              ),
              const SizedBox(height: 20),
              Text('Dates', style: context.text.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [dateButton('Issued', _issueDate, true), dateButton('Due', _dueDate, false)]),
              const SizedBox(height: 20),
              Text('Payment', style: context.text.labelLarge),
              const SizedBox(height: 8),
              pair(field(_method, 'Method (e.g. Orange Money, bank transfer)'), field(_reference, 'Reference / receipt no.')),
              const SizedBox(height: 12),
              field(_notes, 'Notes (shown on the invoice)', lines: 2),
              if (!canEdit && inv.status != InvoiceStatus.voided)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Only admins and owners can edit invoices.', style: context.text.bodySmall?.copyWith(color: muted)),
                ),
            ]),
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InvoicePdfScreen(invoice: _current(status: widget.invoice.status)))),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('View PDF'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => downloadInvoicePdf(context, _current(status: widget.invoice.status)),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download PDF'),
        ),
        TextButton.icon(onPressed: _busy ? null : _share, icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('Share text')),
        if (canEdit && inv.status == InvoiceStatus.draft)
          TextButton(onPressed: _busy ? null : _delete, style: TextButton.styleFrom(foregroundColor: AppColors.danger), child: const Text('Delete')),
        if (canEdit && inv.status != InvoiceStatus.draft)
          TextButton(onPressed: _busy ? null : _void, style: TextButton.styleFrom(foregroundColor: AppColors.danger), child: const Text('Void')),
        if (canEdit && inv.status == InvoiceStatus.draft) ...[
          OutlinedButton(
            onPressed: _busy ? null : () => _save(InvoiceStatus.draft, 'Draft saved'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Save draft'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _save(InvoiceStatus.issued, '${inv.number} issued'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Save and issue'),
          ),
        ],
        if (canEdit && inv.status == InvoiceStatus.issued) ...[
          OutlinedButton(
            onPressed: _busy ? null : () => _save(InvoiceStatus.issued, 'Invoice updated'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Save'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _save(InvoiceStatus.paid, '${inv.number} marked paid'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Mark paid'),
          ),
        ],
        if (canEdit && inv.status == InvoiceStatus.paid)
          FilledButton(
            onPressed: _busy ? null : () => _save(InvoiceStatus.paid, 'Invoice updated'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Save'),
          ),
      ],
    );
  }
}

/// Plain-text invoice for sharing by email or WhatsApp.
String invoiceText(Invoice i) {
  final b = StringBuffer()
    ..writeln('INVOICE ${i.number}')
    ..writeln('Vocation SL · ${AppConfig.supportEmail}')
    ..writeln();
  if (i.issueDate != null) b.writeln('Issued: ${Fmt.date(i.issueDate!)}');
  if (i.dueDate != null) b.writeln('Due: ${Fmt.date(i.dueDate!)}');
  b
    ..writeln()
    ..writeln('Bill to: ${i.billToName}');
  if (i.billToAddress.isNotEmpty) b.writeln(i.billToAddress);
  if (i.billToEmail.isNotEmpty) b.writeln(i.billToEmail);
  b
    ..writeln()
    ..writeln('${i.description}${i.jobTitle.isEmpty ? '' : ' – ${i.jobTitle}'}')
    ..writeln('${i.quantity} × ${money(i.unitPrice, i.currency)} = ${money(i.subtotal, i.currency)}');
  if (i.discount > 0) b.writeln('Discount: − ${money(i.discount, i.currency)}');
  b
    ..writeln('Tax (${i.taxRate.toStringAsFixed(i.taxRate == i.taxRate.roundToDouble() ? 0 : 2)}%): ${money(i.taxAmount, i.currency)}')
    ..writeln('TOTAL: ${money(i.total, i.currency)}');
  if (i.status == InvoiceStatus.paid) {
    b.writeln('PAID${i.paidAt == null ? '' : ' on ${Fmt.date(i.paidAt!)}'}${i.paymentMethod.isEmpty ? '' : ' by ${i.paymentMethod}'}'
        '${i.paymentReference.isEmpty ? '' : ' (ref ${i.paymentReference})'}');
  }
  if (i.status == InvoiceStatus.voided) b.writeln('VOID – this invoice has been cancelled.');
  if (i.notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln(i.notes);
  }
  return b.toString().trimRight();
}
