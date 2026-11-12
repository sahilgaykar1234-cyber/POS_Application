import 'receipt_data.dart';

/// Paper the browser prints on. (USB ESC/POS printing is separate.)
enum PaperSize {
  thermal58('58 mm receipt', '58mm', '48mm'),
  thermal80('80 mm receipt', '80mm', '72mm'),
  a4('A4 page', 'A4', '120mm');

  const PaperSize(this.label, this.page, this.contentWidth);
  final String label;
  final String page; // @page size
  final String contentWidth; // printable width of the receipt column
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// A complete, self-contained HTML page for printing [r] on [paper]. Built
/// only from the saved bill ([ReceiptData]); long names wrap, nothing clips,
/// and the page is exactly as long as the receipt (no blank pages).
String receiptHtml(ReceiptData r, PaperSize paper) {
  final thermal = paper != PaperSize.a4;
  final base = paper == PaperSize.thermal58 ? 11 : 12.5;
  final b = StringBuffer();
  String row(String l, String rgt, {String cls = ''}) =>
      '<div class="row $cls"><span>${_esc(l)}</span><span>${_esc(rgt)}</span></div>';

  b.write('''<!doctype html><html><head><meta charset="utf-8">
<title>Bill ${_esc(r.billNo)}</title>
<style>
@page { size: ${paper.page}${thermal ? ' auto' : ''}; margin: ${thermal ? '0' : '14mm'}; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: #fff; color: #000; }
body { font-family: ${thermal ? '"Courier New", ui-monospace, monospace' : '-apple-system, "Segoe UI", Roboto, Arial, sans-serif'}; font-size: ${base}px; line-height: 1.35; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.r { width: ${paper.contentWidth}; margin: 0 auto; padding: ${thermal ? '3mm 0 6mm' : '0'}; }
.c { text-align: center; }
.logo { display: block; margin: 0 auto 4px; max-width: ${thermal ? '28mm' : '30mm'}; max-height: ${thermal ? '22mm' : '24mm'}; object-fit: contain; }
.shop { font-size: ${base + 5}px; font-weight: 700; margin: 2px 0; word-wrap: break-word; }
.muted { color: #333; font-size: ${base - 1}px; word-wrap: break-word; }
hr { border: 0; border-top: 1px dashed #000; margin: 6px 0; }
.row { display: flex; justify-content: space-between; gap: 6px; }
.row > span:first-child { flex: 1; min-width: 0; word-wrap: break-word; overflow-wrap: anywhere; }
.row > span:last-child { white-space: nowrap; text-align: right; }
.item { margin: 3px 0; break-inside: avoid; }
.item .sub { color: #333; font-size: ${base - 1}px; }
.total { font-size: ${base + 4}px; font-weight: 700; margin-top: 2px; }
.paid { font-weight: 700; }
.small { font-size: ${base - 1.5}px; }
</style></head><body><div class="r">''');

  // Header
  b.write('<div class="c">');
  if (r.logoBase64 != null) {
    final mime = r.logoBase64!.startsWith('/9j/') ? 'image/jpeg' : 'image/png';
    b.write('<img class="logo" src="data:$mime;base64,${r.logoBase64}" alt="">');
  }
  if (r.shopName.isNotEmpty) b.write('<div class="shop">${_esc(r.shopName)}</div>');
  if (r.tagline.isNotEmpty) b.write('<div class="muted">${_esc(r.tagline)}</div>');
  if (r.address.isNotEmpty) b.write('<div class="muted">${_esc(r.address)}</div>');
  if (r.phone.isNotEmpty) b.write('<div class="muted">Ph: ${_esc(r.phone)}</div>');
  if (r.gstNumber.isNotEmpty) b.write('<div class="muted">GSTIN: ${_esc(r.gstNumber)}</div>');
  if (r.header.isNotEmpty) b.write('<div class="muted" style="margin-top:4px">${_esc(r.header)}</div>');
  b.write('</div><hr>');

  // Bill details
  b.write(row('Bill No', r.billNo));
  if (r.orderRef.isNotEmpty && r.orderRef != r.billNo) b.write(row('Order', r.orderRef));
  b.write(row('Date', receiptDate(r.billTime)));
  b.write(row(r.isTakeaway && r.tableNo.isEmpty ? 'Type' : 'Table', r.whereLabel));
  if (r.customerName.isNotEmpty) b.write(row('Customer', r.customerName));
  if (r.customerPhone.isNotEmpty) b.write(row('Mobile', r.customerPhone));
  b.write('<hr>');

  // Items
  b.write(row('Item', 'Amount', cls: 'paid'));
  for (final l in r.lines) {
    final name = l.variant.isEmpty ? l.name : '${l.name} (${l.variant})';
    b.write('<div class="item">${row(name, receiptMoney(l.amount, always2: true))}'
        '<div class="sub">${l.qty} × ${receiptMoney(l.unitPrice, always2: true)}</div></div>');
  }
  b.write('<hr>');

  // Totals
  b.write(row('Subtotal', receiptMoney(r.subtotal, always2: true)));
  if (r.discount > 0) b.write(row('Discount', '−${receiptMoney(r.discount, always2: true)}'));
  if (r.hasGst) {
    final half = (r.gstPercent ?? 0) / 2;
    String pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    b.write(row('CGST ${pct(half)}%', receiptMoney(r.cgst, always2: true)));
    b.write(row('SGST ${pct(half)}%', receiptMoney(r.sgst, always2: true)));
  }
  b.write('<hr>');
  b.write(row('TOTAL', receiptMoney(r.total, always2: true), cls: 'total'));
  b.write('<hr>');

  // Payment
  b.write(row('Payment', r.isPaid ? 'PAID' : 'PENDING', cls: 'paid'));
  if (r.isPaid && r.paymentMethod.isNotEmpty) b.write(row('Paid by', r.paymentMethod));
  if (r.cashReceived != null) b.write(row('Cash received', receiptMoney(r.cashReceived!, always2: true)));
  if (r.changeReturned != null && r.changeReturned! > 0) b.write(row('Change', receiptMoney(r.changeReturned!, always2: true)));

  // Footer
  final thanks = [r.thanks, r.footer].where((s) => s.isNotEmpty).toList();
  if (thanks.isNotEmpty) {
    b.write('<hr><div class="c">');
    for (final t in thanks) {
      b.write('<div>${_esc(t)}</div>');
    }
    b.write('</div>');
  }
  b.write('</div></body></html>');
  return b.toString();
}
