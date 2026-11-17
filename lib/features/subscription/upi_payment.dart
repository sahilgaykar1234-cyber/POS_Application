import '../../core/utils/formatters.dart';

/// Pure helpers for paying the POS subscription by UPI (unit-tested).
///
/// The money goes straight from the cafe to the platform owner's UPI ID; the
/// app never touches it. The cafe then sends the UPI reference number (UTR)
/// as a claim, and the Super Admin approves it after seeing the money arrive.

/// Where cafes pay: platform/payee {upiId, payeeName}.
class UpiPayee {
  const UpiPayee({this.upiId = '', this.payeeName = ''});

  factory UpiPayee.fromMap(Map<String, dynamic>? d) =>
      UpiPayee(upiId: (d?['upiId'] ?? '').toString().trim(), payeeName: (d?['payeeName'] ?? '').toString().trim());

  final String upiId;
  final String payeeName;

  /// Ready to take payments.
  bool get isSet => isValidUpiId(upiId);
}

/// name@bank style UPI ID (VPA).
bool isValidUpiId(String v) => RegExp(r'^[a-zA-Z0-9._-]{2,256}@[a-zA-Z][a-zA-Z0-9.-]{1,63}$').hasMatch(v.trim());

/// The UPI reference number (UTR / RRN) the payer's app shows: 12 digits.
/// Spaces and dashes are ignored. Returns null when it is not 12 digits.
String? normalizeUtr(String v) {
  final d = v.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{12}$').hasMatch(d) ? d : null;
}

/// Short payment note that every UPI app accepts (letters, digits, spaces;
/// max 50 characters), e.g. "CafePOS Flammywood Standard monthly".
String upiNote(String cafeName, String planName, String cycle) {
  final clean = '$cafeName $planName $cycle'.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final note = 'CafePOS $clean';
  return note.length <= 50 ? note : note.substring(0, 50).trim();
}

/// upi://pay link with the amount filled in. Opens GPay / PhonePe / Paytm on
/// a phone; the same text in a QR code can be scanned from any screen.
String upiPayLink({required UpiPayee payee, required double amount, required String note}) {
  final pn = Uri.encodeComponent(payee.payeeName.isEmpty ? 'Cafe POS' : payee.payeeName);
  final tn = Uri.encodeComponent(note);
  return 'upi://pay?pa=${payee.upiId.trim()}&pn=$pn&am=${amount.toStringAsFixed(2)}&cu=INR&tn=$tn';
}

/// Subscription period bought by a payment.
int monthsForCycle(String cycle) => cycle == 'yearly' ? 12 : 1;

/// The new end date after paying for [cycle]: counted from the current end
/// date if it is still ahead, otherwise from [now] (an expired cafe gets a
/// full period from the day it pays).
DateTime renewedUntil({DateTime? currentExpiry, required String cycle, required DateTime now}) {
  final from = currentExpiry != null && currentExpiry.isAfter(now) ? currentExpiry : now;
  return DateTime(from.year, from.month + monthsForCycle(cycle), from.day, from.hour, from.minute);
}

// ------------------------------------------------------------------ claims --

class ClaimStatus {
  ClaimStatus._();
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

/// paymentClaims/{cafeId}: the cafe's latest "we paid" claim.
class PaymentClaim {
  PaymentClaim(this.cafeId, this.data);
  final String cafeId;
  final Map<String, dynamic> data;

  String get cafeName => (data['cafeName'] ?? '').toString();
  String get utr => (data['utr'] ?? '').toString();
  double get amount => data['amount'] is num ? (data['amount'] as num).toDouble() : 0;
  String? get planId => data['planId']?.toString();
  String get planName => (data['planName'] ?? '').toString();
  String get cycle => (data['cycle'] ?? 'monthly').toString();
  String get status => (data['status'] ?? ClaimStatus.pending).toString();
  DateTime? get submittedAt => Fmt.toDate(data['submittedAt']);
  DateTime? get reviewedAt => Fmt.toDate(data['reviewedAt']);
  String get rejectReason => (data['rejectReason'] ?? '').toString();
  String get receiptNo => (data['receiptNo'] ?? '').toString();

  bool get isPending => status == ClaimStatus.pending;
  bool get isRejected => status == ClaimStatus.rejected;
  bool get isApproved => status == ClaimStatus.approved;

  String get cycleLabel => cycle == 'yearly' ? 'Yearly' : 'Monthly';
}
