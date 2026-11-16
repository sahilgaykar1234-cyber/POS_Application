import '../orders/bill.dart';
import '../orders/order_model.dart';
import '../receipt/receipt_data.dart';
import '../receipt/receipt_html.dart';

/// Day-end ("Z") summary of a business day (or any period), from saved
/// bills only (pure, unit-tested).
class DayEndSummary {
  DayEndSummary._({
    required this.bills,
    required this.firstBill,
    required this.lastBill,
    required this.billed,
    required this.discounts,
    required this.gst,
    required this.collected,
    required this.byMethod,
    required this.unpaidCount,
    required this.unpaidAmount,
    required this.cancelledCount,
    required this.cancelledAmount,
    required this.dineIn,
    required this.takeaway,
  });

  final int bills; // not cancelled
  final String firstBill, lastBill;
  final double billed, discounts, gst, collected;
  final Map<PaymentMethod, double> byMethod;
  final int unpaidCount, cancelledCount, dineIn, takeaway;
  final double unpaidAmount, cancelledAmount;

  static DayEndSummary of(Iterable<PosOrder> orders) {
    final all = orders.toList()..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    final live = all.where((o) => !o.isCancelled).toList();
    final cancelled = all.where((o) => o.isCancelled).toList();
    final byMethod = {for (final m in PaymentMethod.values) m: 0.0};
    var collected = 0.0;
    for (final o in live.where((o) => o.isPaid)) {
      collected += o.totalPrice;
      final m = methodFromStatus(o.paymentStatus);
      if (m != null) byMethod[m] = byMethod[m]! + o.totalPrice;
    }
    final numbered = all.where((o) => (o.data['billSeq'] as num?) != null).toList()
      ..sort((a, b) => (a.data['billSeq'] as num).compareTo(b.data['billSeq'] as num));
    final unpaid = live.where((o) => !o.isPaid).toList();
    final take = live.where((o) => o.isTakeaway).length;
    return DayEndSummary._(
      bills: live.length,
      firstBill: numbered.isEmpty ? '—' : numbered.first.billNo,
      lastBill: numbered.isEmpty ? '—' : numbered.last.billNo,
      billed: live.fold(0.0, (t, o) => t + o.totalPrice),
      discounts: live.fold(0.0, (t, o) => t + o.discount),
      gst: live.fold(0.0, (t, o) => t + o.gstAmount),
      collected: collected,
      byMethod: byMethod,
      unpaidCount: unpaid.length,
      unpaidAmount: unpaid.fold(0.0, (t, o) => t + o.totalPrice),
      cancelledCount: cancelled.length,
      cancelledAmount: cancelled.fold(0.0, (t, o) => t + o.totalPrice),
      dineIn: live.length - take,
      takeaway: take,
    );
  }
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Printable day-end report on receipt paper / A4.
String dayEndHtml(DayEndSummary s, {required String shopName, required String periodLabel, required DateTime printedAt, PaperSize paper = PaperSize.thermal80}) {
  String m(num v) => receiptMoney(v, always2: true);
  String row(String l, String r, {bool bold = false}) =>
      '<div class="row${bold ? ' b' : ''}"><span>${_esc(l)}</span><span>${_esc(r)}</span></div>';
  final thermal = paper != PaperSize.a4;
  final b = StringBuffer()
    ..write('''<!doctype html><html><head><meta charset="utf-8"><title>Day-end report</title><style>
@page { size: ${paper.page}${thermal ? ' auto' : ''}; margin: ${thermal ? '0' : '14mm'}; }
body { margin:0; font-family: ${thermal ? '"Courier New", monospace' : 'Arial, sans-serif'}; font-size: ${paper == PaperSize.thermal58 ? 11 : 12.5}px; color:#000; }
.r { width: ${paper.contentWidth}; margin: 0 auto; padding: ${thermal ? '3mm 0 6mm' : '0'}; }
.c { text-align:center; } .t { font-size: 1.4em; font-weight:700; } hr { border:0; border-top:1px dashed #000; margin:6px 0; }
.row { display:flex; justify-content:space-between; gap:6px; } .b { font-weight:700; }
</style></head><body><div class="r">''')
    ..write('<div class="c t">${_esc(shopName.isEmpty ? 'Day-end report' : shopName)}</div>')
    ..write('<div class="c b">DAY-END REPORT</div><div class="c">${_esc(periodLabel)}</div><hr>')
    ..write(row('Bills', '${s.bills}'))
    ..write(row('First bill', s.firstBill))
    ..write(row('Last bill', s.lastBill))
    ..write(row('Dine-in / Takeaway', '${s.dineIn} / ${s.takeaway}'))
    ..write('<hr>')
    ..write(row('Billed', m(s.billed), bold: true))
    ..write(row('Discounts', m(s.discounts)))
    ..write(row('GST', m(s.gst)))
    ..write('<hr>')
    ..write(row('Collected', m(s.collected), bold: true));
  for (final e in s.byMethod.entries) {
    b.write(row('  ${e.key.label}', m(e.value)));
  }
  b
    ..write(row('Unpaid (${s.unpaidCount})', m(s.unpaidAmount)))
    ..write('<hr>')
    ..write(row('Cancelled (${s.cancelledCount})', m(s.cancelledAmount)))
    ..write('<hr><div class="c">Printed ${_esc(receiptDate(printedAt))}</div>')
    ..write('</div></body></html>');
  return b.toString();
}
