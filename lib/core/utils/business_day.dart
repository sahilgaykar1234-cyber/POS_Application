/// The cafe's "business day": it does not end at midnight but at a time the
/// cafe chooses (Settings › Business day ends at, default 5:00 AM). A shop
/// open 7 PM – 2 AM then sees the whole night as one day everywhere
/// (dashboard, recent bills, tokens, kitchen, reports, orders).
///
/// Pure date maths (unit-tested); the end time comes from Settings.
class BusinessDay {
  BusinessDay._();

  /// Default: the next day starts at 5:00 AM.
  static const int defaultCutoffMinutes = 5 * 60;

  /// Latest allowed end of the business day (noon).
  static const int maxCutoffMinutes = 12 * 60;

  static int _cutoff = defaultCutoffMinutes;

  /// Minutes after midnight when the next business day starts.
  static int get cutoffMinutes => _cutoff;

  static void setCutoff(int minutes) => _cutoff = minutes.clamp(0, maxCutoffMinutes);

  /// The date (00:00) naming the business day that [t] belongs to, e.g.
  /// 13 Nov 1:30 AM → 12 Nov (with a 5 AM cutoff).
  static DateTime dateOf(DateTime t) {
    final shifted = t.subtract(Duration(minutes: _cutoff));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  /// When business day [date] starts (its date + the cutoff time).
  static DateTime startOf(DateTime date) => DateTime(date.year, date.month, date.day, 0, _cutoff);

  /// [start, end) of the business days [fromDate]..[toDate] (inclusive).
  static (DateTime, DateTime) range(DateTime fromDate, DateTime toDate) =>
      (startOf(fromDate), startOf(DateTime(toDate.year, toDate.month, toDate.day + 1)));

  /// [start, end) of the business day running at [now].
  static (DateTime, DateTime) today([DateTime? now]) {
    final d = dateOf(now ?? DateTime.now());
    return range(d, d);
  }

  /// When the current business day ends (the screens refresh then).
  static DateTime nextChange([DateTime? now]) => today(now).$2;

  /// True if [t] is inside [range].
  static bool inRange(DateTime t, (DateTime, DateTime) range) => !t.isBefore(range.$1) && t.isBefore(range.$2);

  /// "5:00 AM" style label for [minutes] after midnight.
  static String label(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  /// "HH:mm" ↔ minutes (stored in Settings as text).
  static int? parse(Object? v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((v ?? '').toString().trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  static String format(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}
