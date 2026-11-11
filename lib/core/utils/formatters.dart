import 'package:cloud_firestore/cloud_firestore.dart';

/// Small formatting helpers (no extra packages needed).
class Fmt {
  Fmt._();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Accepts Timestamp, DateTime, or null.
  static DateTime? toDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  /// 05 Nov 2026
  static String date(Object? v, {String empty = '—'}) {
    final d = toDate(v);
    if (d == null) return empty;
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
  }

  /// 05 Nov 2026, 14:05
  static String dateTime(Object? v, {String empty = '—'}) {
    final d = toDate(v);
    if (d == null) return empty;
    return '${date(d)}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// ₹1,23,456 (Indian grouping), decimals only when needed.
  static String money(num v, {String symbol = '₹'}) {
    final neg = v < 0;
    final abs = v.abs();
    final whole = abs.truncate();
    final frac = abs - whole;
    final s = whole.toString();
    String grouped;
    if (s.length <= 3) {
      grouped = s;
    } else {
      final last3 = s.substring(s.length - 3);
      var rest = s.substring(0, s.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      grouped = '${parts.join(',')},$last3';
    }
    final decimals = frac > 0.004 ? '.${(frac * 100).round().toString().padLeft(2, '0')}' : '';
    return '${neg ? '-' : ''}$symbol$grouped$decimals';
  }
}
