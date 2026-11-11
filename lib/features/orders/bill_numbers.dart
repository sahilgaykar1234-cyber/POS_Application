// Sequential bill numbers per cafe, restarting every Indian financial year
// (1 April). Format: "26-27/0042". Pure helpers (unit-tested).

/// Financial year label for [d], e.g. "2026-27" (Apr 2026 – Mar 2027).
String financialYear(DateTime d) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  return '$start-${((start + 1) % 100).toString().padLeft(2, '0')}';
}

/// Short form used in the bill number: "26-27".
String financialYearShort(DateTime d) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  String two(int y) => (y % 100).toString().padLeft(2, '0');
  return '${two(start)}-${two(start + 1)}';
}

/// "26-27/0042"
String formatBillNumber(DateTime d, int seq) => '${financialYearShort(d)}/${seq.toString().padLeft(4, '0')}';

/// Counter document name for the bill series of [d]'s financial year.
String billCounterName(DateTime d) => 'bills_${financialYear(d)}';

/// The bill number to show for an order: the stored sequential number, or
/// (for orders made before bill series existed) the old id-based one.
String displayBillNo(Map<String, dynamic> order, String orderId, {int idChars = 6}) {
  final stored = order['billNo'];
  if (stored is String && stored.isNotEmpty) return stored;
  if (orderId.isEmpty) return '';
  return '#${orderId.substring(0, orderId.length > idChars ? idChars : orderId.length).toUpperCase()}';
}

/// Sortable key across years: 2026-27 bill 42 → 202600042. Stored on each
/// order so "the latest bill" is one simple query.
int billKey(DateTime d, int seq) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  return start * 100000 + seq;
}

/// Sequence number inside its financial year from a stored [billKey], or
/// null if [key] belongs to a different financial year than [d].
int? seqInYear(int? key, DateTime d) {
  if (key == null) return null;
  final start = d.month >= 4 ? d.year : d.year - 1;
  return key ~/ 100000 == start ? key % 100000 : null;
}

/// Decides the next bill number. The previous bill decides it: normally the
/// counter continues (it is what keeps two devices from sharing a number),
/// but if the bill that last used the counter was deleted, numbering resumes
/// right after the latest bill that still exists ([lastSeqInOrders]).
/// Never goes back to a number an existing bill already has.
int nextBillSeq({
  required int? counterNext,
  required bool counterLastOrderExists,
  required int lastSeqInOrders,
}) {
  final afterLast = lastSeqInOrders + 1;
  if (counterNext == null || !counterLastOrderExists) return afterLast;
  return counterNext > afterLast ? counterNext : afterLast;
}
