import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin/features/invoices.dart' show InvoiceStatusPill, money;
import '../../../core/config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../widgets/invoice_pdf.dart';
import '../../../widgets/skeletons.dart';
import '../../../widgets/states.dart';
import '../../providers.dart';
import '../../widgets.dart';

/// Invoices Vocation SL has issued for the company's job listings.
class EmployerInvoicesScreen extends ConsumerWidget {
  const EmployerInvoicesScreen({super.key});

  void _view(BuildContext context, Invoice i) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InvoicePdfScreen(invoice: i)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employerInvoicesProvider);
    final now = DateTime.now();
    return EmployerPage(
      title: 'Invoices',
      subtitle: 'Invoices for your job listings. Quote the invoice number when you pay.',
      onRefresh: () async => ref.invalidate(employerInvoicesProvider),
      children: [
        async.when(
          skipLoadingOnRefresh: true,
          loading: () => const DashboardSkeleton(),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(employerInvoicesProvider)),
          data: (all) {
            double sum(Iterable<Invoice> l) => l.fold(0, (s, i) => s + i.total);
            final due = all.where((i) => i.status == InvoiceStatus.issued);
            final overdue = all.where((i) => i.isOverdueAt(now));
            final paid = all.where((i) => i.status == InvoiceStatus.paid);
            final currency = all.isEmpty ? 'SLE' : all.first.currency;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatGrid(children: [
                StatTile(label: 'Amount due', value: money(sum(due), currency), detail: '${due.length} unpaid', icon: Icons.hourglass_bottom_rounded),
                StatTile(
                  label: 'Overdue',
                  value: money(sum(overdue), currency),
                  detail: '${overdue.length} past due date',
                  icon: Icons.warning_amber_rounded,
                  attention: overdue.isNotEmpty,
                ),
                StatTile(label: 'Paid', value: money(sum(paid), currency), detail: '${paid.length} invoice${paid.length == 1 ? '' : 's'}', icon: Icons.payments_outlined),
              ]),
              const SizedBox(height: 20),
              TableCard(
                empty: const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No invoices yet',
                  message: 'When Vocation SL issues an invoice for one of your job listings, it appears here and you get an alert.',
                ),
                columns: const [
                  DataColumn(label: Text('Invoice')),
                  DataColumn(label: Text('Job')),
                  DataColumn(label: Text('Issued')),
                  DataColumn(label: Text('Due')),
                  DataColumn(label: Text('Total'), numeric: true),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('PDF')),
                ],
                rows: [
                  for (final i in all)
                    DataRow(onSelectChanged: (_) => _view(context, i), cells: [
                      DataCell(Text(i.number, style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(i.jobTitle.isEmpty ? '—' : i.jobTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text(i.issueDate == null ? '—' : Fmt.dateShort(i.issueDate!))),
                      DataCell(Text(i.dueDate == null ? '—' : Fmt.dateShort(i.dueDate!))),
                      DataCell(Text(money(i.total, i.currency))),
                      DataCell(InvoiceStatusPill(i, now: now)),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'View PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _view(context, i)),
                        IconButton(tooltip: 'Download PDF', icon: const Icon(Icons.download_rounded), onPressed: () => downloadInvoicePdf(context, i)),
                      ])),
                    ]),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Questions about an invoice? Email ${AppConfig.supportEmail} with the invoice number.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]);
          },
        ),
      ],
    );
  }
}
