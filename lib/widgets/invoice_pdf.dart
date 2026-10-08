import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import '../core/config/app_config.dart';
import '../models/models.dart';
import 'common.dart';
import 'skeletons.dart';
import 'states.dart';

final _money = NumberFormat('#,##0.00');
final _date = DateFormat('d MMMM yyyy');

const _green = PdfColor.fromInt(0xFF3F7A1F);
const _brand = PdfColor.fromInt(0xFF7DB43A);
const _ink = PdfColor.fromInt(0xFF14171A);
const _muted = PdfColor.fromInt(0xFF5E6670);
const _line = PdfColor.fromInt(0xFFE3E7E0);
const _tint = PdfColor.fromInt(0xFFEFF6E6);

const _logoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path d="M26 14 L50 86 L74 14" fill="none" stroke="#14171A" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M28 86 L50 20 L72 86" fill="none" stroke="#7DB43A" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

String invoiceFileName(Invoice i) => '${i.number.isEmpty ? 'invoice' : i.number}.pdf';

/// A one-page A4 invoice for a job listing.
Future<Uint8List> buildInvoicePdf(Invoice i) async {
  String m(double v) => '${i.currency} ${_money.format(v)}';
  final doc = pw.Document(title: 'Invoice ${i.number}', author: 'Vocation SL', creator: 'Vocation SL');

  pw.Widget label(String t) => pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 8, color: _muted, letterSpacing: 1, fontWeight: pw.FontWeight.bold));
  pw.Widget row(String l, String v, {bool strong = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(l, style: pw.TextStyle(fontSize: strong ? 12 : 10, color: strong ? _ink : _muted, fontWeight: strong ? pw.FontWeight.bold : null)),
          pw.Text(v, style: pw.TextStyle(fontSize: strong ? 13 : 10, color: color ?? _ink, fontWeight: strong ? pw.FontWeight.bold : null)),
        ]),
      );

  final (statusText, statusColor) = switch (i.status) {
    InvoiceStatus.paid => ('PAID', _green),
    InvoiceStatus.voided => ('VOID', PdfColors.red700),
    InvoiceStatus.issued => ('DUE', const PdfColor.fromInt(0xFFB4570F)),
    InvoiceStatus.draft => ('DRAFT', _muted),
  };

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(44, 44, 44, 40),
    build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // Header
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SvgImage(svg: _logoSvg, width: 40, height: 40),
        pw.SizedBox(width: 10),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Vocation ', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.TextSpan(text: 'SL', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _brand)),
            ]),
          ),
          pw.Text('Jobs in Sierra Leone', style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.Text(AppConfig.supportEmail, style: const pw.TextStyle(fontSize: 9, color: _muted)),
        ]),
        pw.Spacer(),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('INVOICE', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: _ink, letterSpacing: 1)),
          pw.SizedBox(height: 2),
          pw.Text(i.number, style: const pw.TextStyle(fontSize: 11, color: _muted)),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: statusColor, width: 1.2), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text(statusText, style: pw.TextStyle(fontSize: 10, color: statusColor, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
          ),
        ]),
      ]),
      pw.SizedBox(height: 28),
      pw.Container(height: 3, color: _green),
      pw.SizedBox(height: 22),

      // Bill to / dates
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label('Bill to'),
            pw.SizedBox(height: 6),
            pw.Text(i.billToName.isEmpty ? '-' : i.billToName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
            if (i.billToAddress.isNotEmpty) pw.Text(i.billToAddress, style: const pw.TextStyle(fontSize: 10, color: _ink)),
            if (i.billToEmail.isNotEmpty) pw.Text(i.billToEmail, style: const pw.TextStyle(fontSize: 10, color: _muted)),
          ]),
        ),
        pw.SizedBox(width: 24),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          label('Issue date'),
          pw.SizedBox(height: 4),
          pw.Text(i.issueDate == null ? 'Not issued' : _date.format(i.issueDate!), style: const pw.TextStyle(fontSize: 10, color: _ink)),
          pw.SizedBox(height: 10),
          label('Due date'),
          pw.SizedBox(height: 4),
          pw.Text(i.dueDate == null ? '-' : _date.format(i.dueDate!), style: const pw.TextStyle(fontSize: 10, color: _ink)),
        ]),
      ]),
      pw.SizedBox(height: 28),

      // Line items
      pw.Table(
        columnWidths: const {0: pw.FlexColumnWidth(5), 1: pw.FlexColumnWidth(1.2), 2: pw.FlexColumnWidth(2.2), 3: pw.FlexColumnWidth(2.4)},
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: .8), bottom: pw.BorderSide(color: _line, width: .8)),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _tint),
            children: [
              for (final (t, right) in const [('Description', false), ('Qty', true), ('Unit price', true), ('Amount', true)])
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: pw.Text(t, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green)),
                ),
            ],
          ),
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(i.description, style: pw.TextStyle(fontSize: 10, color: _ink, fontWeight: pw.FontWeight.bold)),
                if (i.jobTitle.isNotEmpty) pw.Text('Job: ${i.jobTitle}', style: const pw.TextStyle(fontSize: 9, color: _muted)),
              ]),
            ),
            for (final t in ['${i.quantity}', m(i.unitPrice), m(i.subtotal)])
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: pw.Text(t, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10, color: _ink)),
              ),
          ]),
        ],
      ),
      pw.SizedBox(height: 16),

      // Totals
      pw.Row(children: [
        pw.Spacer(flex: 5),
        pw.Expanded(
          flex: 4,
          child: pw.Column(children: [
            row('Subtotal', m(i.subtotal)),
            if (i.discount > 0) row('Discount', '- ${m(i.discount)}'),
            row('Tax / GST (${i.taxRate == i.taxRate.roundToDouble() ? i.taxRate.toStringAsFixed(0) : i.taxRate.toStringAsFixed(2)}%)', m(i.taxAmount)),
            pw.Divider(color: _ink, thickness: 1),
            row('Total', m(i.total), strong: true),
            if (i.status == InvoiceStatus.paid) row('Amount due', m(0), color: _green),
            if (i.status == InvoiceStatus.issued) row('Amount due', m(i.total), strong: true, color: const PdfColor.fromInt(0xFFB4570F)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 24),

      // Payment
      if (i.status == InvoiceStatus.paid)
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: _tint, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Text(
            [
              'Paid${i.paidAt == null ? '' : ' on ${_date.format(i.paidAt!)}'}',
              if (i.paymentMethod.isNotEmpty) 'by ${i.paymentMethod}',
              if (i.paymentReference.isNotEmpty) '(reference ${i.paymentReference})',
            ].join(' '),
            style: pw.TextStyle(fontSize: 10, color: _green, fontWeight: pw.FontWeight.bold),
          ),
        ),
      if (i.status == InvoiceStatus.voided)
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: PdfColors.red50, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Text('This invoice has been cancelled and is not payable.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.red800)),
        ),
      if (i.status == InvoiceStatus.issued)
        pw.Text('Please quote ${i.number} as the reference when you pay. Questions about this invoice: ${AppConfig.supportEmail}.',
            style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
      if (i.notes.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        label('Notes'),
        pw.SizedBox(height: 4),
        pw.Text(i.notes, style: const pw.TextStyle(fontSize: 10, color: _ink)),
      ],
      pw.Spacer(),
      pw.Divider(color: _line),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Vocation SL · ${AppConfig.supportEmail}', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        pw.Text('Thank you for hiring with Vocation SL.', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
      ]),
    ]),
  ));
  return doc.save();
}

/// Saves the PDF: a download in the browser, the share/save sheet on phones.
Future<void> downloadInvoicePdf(BuildContext context, Invoice i) async {
  try {
    final bytes = await buildInvoicePdf(i);
    await Printing.sharePdf(bytes: bytes, filename: invoiceFileName(i));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Shows the invoice PDF inside the app, with Download and Print.
class InvoicePdfScreen extends StatefulWidget {
  const InvoicePdfScreen({super.key, required this.invoice});
  final Invoice invoice;

  @override
  State<InvoicePdfScreen> createState() => _InvoicePdfScreenState();
}

class _InvoicePdfScreenState extends State<InvoicePdfScreen> {
  late Future<Uint8List> _pdf = buildInvoicePdf(widget.invoice);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _pdf,
        builder: (context, snap) => Scaffold(
          appBar: AppBar(
            title: Text('Invoice ${widget.invoice.number}'),
            actions: [
              if (snap.hasData) ...[
                IconButton(
                  tooltip: 'Print',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () => Printing.layoutPdf(name: invoiceFileName(widget.invoice), onLayout: (_) async => snap.data!),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: () => Printing.sharePdf(bytes: snap.data!, filename: invoiceFileName(widget.invoice)),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download'),
                  ),
                ),
              ],
            ],
          ),
          body: switch (snap) {
            AsyncSnapshot(hasError: true) => ErrorState(error: snap.error!, onRetry: () => setState(() => _pdf = buildInvoicePdf(widget.invoice))),
            AsyncSnapshot(hasData: false) => const DocumentSkeleton(),
            _ => PdfViewer.data(
                snap.data!,
                sourceName: invoiceFileName(widget.invoice),
                params: const PdfViewerParams(backgroundColor: Color(0xFFE9ECE6)),
              ),
          },
        ),
      );
}
