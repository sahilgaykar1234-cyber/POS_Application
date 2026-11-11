/// Bill maths, kept in one pure place so every screen (POS, settle sheet,
/// receipt) agrees.
///
/// IMPORTANT: with no discount this is EXACTLY the formula the app always used:
///   total = subtotal + subtotal × (gst% / 100)     (GST only when enabled)
/// A discount is taken off the subtotal before GST is added.
enum DiscountType { none, percent, amount }

class Bill {
  const Bill({
    required this.subtotal,
    required this.discount,
    required this.gst,
    required this.total,
    required this.gstPercent,
    required this.gstEnabled,
  });

  final double subtotal;
  final double discount;
  final double gst;
  final double total;
  final double gstPercent;
  final bool gstEnabled;

  double get taxable => subtotal - discount;

  /// Items are maps in the stored order shape: {price, qty, ...}.
  static double subtotalOf(Iterable<Map<String, dynamic>> items) {
    double subtotal = 0;
    for (final item in items) {
      subtotal += ((item['price'] ?? 0.0) as num).toDouble() * ((item['qty'] ?? 1) as num).toInt();
    }
    return subtotal;
  }

  static Bill compute({
    required Iterable<Map<String, dynamic>> items,
    required bool gstEnabled,
    required double gstPercent,
    DiscountType discountType = DiscountType.none,
    double discountValue = 0,
  }) {
    final subtotal = subtotalOf(items);
    double discount = 0;
    if (discountType == DiscountType.percent && discountValue > 0) {
      discount = subtotal * (discountValue.clamp(0, 100) / 100.0);
    } else if (discountType == DiscountType.amount && discountValue > 0) {
      discount = discountValue > subtotal ? subtotal : discountValue;
    }
    final taxable = subtotal - discount;
    final gst = gstEnabled ? taxable * (gstPercent / 100.0) : 0.0;
    return Bill(
      subtotal: subtotal,
      discount: discount,
      gst: gst,
      total: taxable + gst,
      gstPercent: gstPercent,
      gstEnabled: gstEnabled,
    );
  }

  static DiscountType parseType(Object? v) => switch (v) {
        'percent' => DiscountType.percent,
        'amount' => DiscountType.amount,
        _ => DiscountType.none,
      };
}

/// Payment methods. Stored in the order as paymentStatus `paid_<method>`
/// (the format receipts/reports already read) plus `paymentMethod`.
enum PaymentMethod { cash, upi, card }

extension PaymentMethodX on PaymentMethod {
  String get status => 'paid_$name';
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.upi => 'UPI',
        PaymentMethod.card => 'Card',
      };
}

bool isPaidStatus(String? s) => (s ?? '').startsWith('paid');

PaymentMethod? methodFromStatus(String? s) => switch (s) {
      'paid_cash' => PaymentMethod.cash,
      'paid_upi' => PaymentMethod.upi,
      'paid_card' => PaymentMethod.card,
      _ => null,
    };
