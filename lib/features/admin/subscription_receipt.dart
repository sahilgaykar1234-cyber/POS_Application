import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/formatters.dart';
import 'admin_service.dart';

/// Builds a simple A5 receipt for a SaaS subscription payment.
/// (Uses "Rs." because the built-in PDF fonts have no ₹ glyph.)
Future<Uint8List> buildSubscriptionReceiptPdf(SubscriptionPayment p, {String? cafeAddress}) async {
  final doc = pw.Document(title: 'Receipt ${p.receiptNo}', author: AppConfig.appName);
  final money = Fmt.money(p.amount, symbol: 'Rs. ');

  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 120, child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(v.isEmpty ? '-' : v)),
          ],
        ),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(AppConfig.appName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text('PAYMENT RECEIPT', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Text(AppConfig.appTagline, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.Divider(height: 24),
          row('Receipt No.', p.receiptNo),
          row('Date', Fmt.date(p.paidAt)),
          pw.SizedBox(height: 10),
          pw.Text('Received from', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(p.cafeName, style: const pw.TextStyle(fontSize: 13)),
          if (cafeAddress != null && cafeAddress.isNotEmpty) pw.Text(cafeAddress, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 14),
          pw.Text('Payment details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          row('Plan', p.planName),
          row('Period', p.periodStart == null && p.periodEnd == null ? '' : '${Fmt.date(p.periodStart)} to ${Fmt.date(p.periodEnd)}'),
          row('Method', p.method),
          row('Reference / Txn ID', p.referenceId),
          if (p.notes.isNotEmpty) row('Notes', p.notes),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Amount received', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(money, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Text('This is a computer-generated receipt for the POS software subscription.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Opens the share/download dialog (web: downloads the PDF).
Future<void> shareSubscriptionReceipt(SubscriptionPayment p, {String? cafeAddress}) async {
  final bytes = await buildSubscriptionReceiptPdf(p, cafeAddress: cafeAddress);
  await Printing.sharePdf(bytes: bytes, filename: '${p.receiptNo}.pdf');
}
