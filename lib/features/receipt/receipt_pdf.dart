import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_data.dart';

/// The full bill as a PDF, laid out like the printed receipt (same lines, in
/// the same order) so the customer gets every detail on WhatsApp: logo,
/// cafe details, GSTIN, bill no, items, discount, CGST/SGST, total and
/// payment. Built only from the saved bill ([ReceiptData]). Bills stay in
/// English, like the printed receipt.
///
/// One long receipt-width page (no page breaks), easy to read on a phone.
Future<Uint8List> buildReceiptPdf(ReceiptData r, {ReceiptPdfFonts? fonts}) async {
  final f = fonts ?? await ReceiptPdfFonts.load();
  final doc = pw.Document(
    title: 'Bill ${r.billNo}',
    author: r.shopName.isEmpty ? 'Cafe POS' : r.shopName,
    creator: 'Cafe POS',
    theme: pw.ThemeData.withFont(base: f.regular, bold: f.bold, fontFallback: f.fallback),
  );

  const ink = PdfColor.fromInt(0xFF101828);
  const muted = PdfColor.fromInt(0xFF475467);
  const line = PdfColor.fromInt(0xFFD0D5DD);
  const paid = PdfColor.fromInt(0xFF067647);
  const danger = PdfColor.fromInt(0xFFB42318);

  pw.Widget text(String s, {double size = 10, bool bold = false, PdfColor color = ink, pw.TextAlign? align}) =>
      pw.Text(s, textAlign: align, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color));

  pw.Widget row(String l, String rgt, {double size = 10, bool bold = false, PdfColor color = ink, PdfColor? labelColor}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: text(l, size: size, bold: bold, color: labelColor ?? color)),
            pw.SizedBox(width: 8),
            text(rgt, size: size, bold: bold, color: color, align: pw.TextAlign.right),
          ],
        ),
      );

  pw.Widget dashed() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Container(
          height: 0,
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: line, width: 0.8, style: pw.BorderStyle.dashed))),
        ),
      );

  pw.Widget solid() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Container(height: 1.2, color: ink),
      );

  String money(double v) => receiptMoney(v, always2: true);

  pw.ImageProvider? logo;
  if (r.logoBase64 != null) {
    try {
      logo = pw.MemoryImage(base64Decode(r.logoBase64!));
    } catch (_) {
      logo = null; // a broken / unsupported logo never stops the bill
    }
  }

  final header = <pw.Widget>[
    if (logo != null) pw.Container(height: 52, margin: const pw.EdgeInsets.only(bottom: 6), child: pw.Image(logo, fit: pw.BoxFit.contain)),
    if (r.shopName.isNotEmpty) text(r.shopName, size: 15, bold: true, align: pw.TextAlign.center),
    if (r.tagline.isNotEmpty) text(r.tagline, color: muted, align: pw.TextAlign.center),
    if (r.address.isNotEmpty) text(r.address, color: muted, align: pw.TextAlign.center),
    if (r.phone.isNotEmpty) text('Ph: ${r.phone}', color: muted, align: pw.TextAlign.center),
    if (r.gstNumber.isNotEmpty) text('GSTIN: ${r.gstNumber}', color: muted, align: pw.TextAlign.center),
    if (r.header.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: text(r.header, color: muted, align: pw.TextAlign.center)),
  ];

  String pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  final half = (r.gstPercent ?? 0) / 2;
  final thanks = [r.thanks, r.footer].where((s) => s.isNotEmpty).toList();

  doc.addPage(
    pw.Page(
      // Receipt width (about 90 mm) and as long as the bill.
      pageFormat: const PdfPageFormat(90 * PdfPageFormat.mm, double.infinity, marginAll: 7 * PdfPageFormat.mm),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: header),
          dashed(),
          if (r.isCancelled) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: danger, width: 1.2)),
              child: text('CANCELLED${r.voidReason.isEmpty ? '' : ' · ${r.voidReason}'}', bold: true, color: danger, align: pw.TextAlign.center),
            ),
            pw.SizedBox(height: 6),
          ],
          row('Bill No', r.billNo, bold: true, labelColor: muted),
          if (r.orderRef.isNotEmpty && r.orderRef != r.billNo) row('Order', r.orderRef, labelColor: muted),
          row('Date', receiptDate(r.billTime), labelColor: muted),
          row(r.isTakeaway && r.tableNo.isEmpty ? 'Type' : 'Table', r.whereLabel, labelColor: muted),
          if (r.customerName.isNotEmpty) row('Customer', r.customerName, labelColor: muted),
          dashed(),
          row('ITEM', 'AMOUNT', size: 8.5, bold: true, color: muted),
          for (final l in r.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  row(l.variant.isEmpty ? l.name : '${l.name} (${l.variant})', money(l.amount), bold: true),
                  text('${l.qty} × ${money(l.unitPrice)}', size: 9, color: muted),
                ],
              ),
            ),
          dashed(),
          row('Subtotal', money(r.subtotal), labelColor: muted),
          if (r.discount > 0) row('Discount', '-${money(r.discount)}', labelColor: muted),
          if (r.hasGst) ...[
            row('CGST ${pct(half)}%', money(r.cgst), labelColor: muted),
            row('SGST ${pct(half)}%', money(r.sgst), labelColor: muted),
          ],
          solid(),
          row('TOTAL', money(r.total), size: 14, bold: true),
          solid(),
          row('Payment', r.isPaid ? 'PAID' : 'PENDING', bold: true, color: r.isPaid ? paid : danger),
          if (r.isPaid && r.paymentMethod.isNotEmpty) row('Paid by', r.paymentMethod, labelColor: muted),
          if (r.cashReceived != null) row('Cash received', money(r.cashReceived!), labelColor: muted),
          if (r.changeReturned != null && r.changeReturned! > 0) row('Change', money(r.changeReturned!), labelColor: muted),
          if (thanks.isNotEmpty) ...[
            dashed(),
            for (final t in thanks) text(t, color: muted, align: pw.TextAlign.center),
          ],
        ],
      ),
    ),
  );
  return doc.save();
}

/// The bundled fonts (Inter, with Noto for Hindi / Gujarati names), so the
/// PDF looks the same on every phone and shows ₹ correctly. Loaded once.
class ReceiptPdfFonts {
  ReceiptPdfFonts(this.regular, this.bold, this.fallback);
  final pw.Font regular;
  final pw.Font bold;
  final List<pw.Font> fallback;

  static ReceiptPdfFonts? _cache;

  static Future<ReceiptPdfFonts> load() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> ttf(String file) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
    return _cache = ReceiptPdfFonts(
      await ttf('Inter-Regular.ttf'),
      await ttf('Inter-Bold.ttf'),
      [await ttf('NotoSansDevanagari-Regular.ttf'), await ttf('NotoSansGujarati-Regular.ttf')],
    );
  }
}

/// "Bill-26-27-0002.pdf"
String receiptPdfFileName(ReceiptData r) => 'Bill-${r.billNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}.pdf';
