import '../utils/business_day.dart';
import '../utils/formatters.dart';

/// Cafe lifecycle status (set by the Super Admin).
class CafeStatus {
  CafeStatus._();
  static const active = 'active';
  static const inactive = 'inactive';
  static const suspended = 'suspended';
  static const deleted = 'deleted';
  static const all = [active, inactive, suspended, deleted];
}

/// Subscription status (cafes/{id}.subscription.status).
class SubscriptionStatus {
  SubscriptionStatus._();
  static const trial = 'trial';
  static const active = 'active';
  static const pending = 'pending';
  static const expired = 'expired';
  static const suspended = 'suspended';

  /// Will not renew: usable until the expiry date, then blocked.
  static const cancelled = 'cancelled';
  static const all = [trial, active, pending, expired, suspended, cancelled];
}

enum CafeAccessState {
  /// POS fully usable.
  allowed,

  /// Usable, but show a warning banner (expiring soon / payment pending).
  allowedWithWarning,

  /// The subscription has expired but is inside the grace period: the POS
  /// still works, with a red "renew now" banner.
  grace,

  /// Data still in the old global collections — waiting for migration.
  migrating,

  /// POS blocked; data is kept.
  blocked,
}

class CafeAccess {
  const CafeAccess(this.state, {this.title = '', this.message = '', this.canRenew = false});

  final CafeAccessState state;
  final String title;
  final String message;

  /// Paying the subscription would fix this (expiring, pending, in grace or
  /// expired). False for a suspended / closed cafe: only the admin can help.
  final bool canRenew;

  bool get canUsePos =>
      state == CafeAccessState.allowed || state == CafeAccessState.allowedWithWarning || state == CafeAccessState.grace;
}

/// Days before expiry at which staff start seeing a reminder.
const int kExpiryWarningDays = 7;

/// Days the POS keeps working after the expiry date, so a cafe is never cut
/// off in the middle of service and has time to pay.
const int kGraceDays = 3;

/// When the grace period ends: the end of the cafe's business day that is
/// running [kGraceDays] days after [expiry] (e.g. expiry 10 Nov 20:00 with a
/// 5 AM day end → blocked 14 Nov 05:00, after that night's service).
///
/// Always within 4 days of the expiry, which is what firestore.rules allow
/// (`cafeOperational`), so the app never lets a cafe work longer than the
/// server does.
DateTime graceEndFor(DateTime expiry) => BusinessDay.nextChange(expiry.add(const Duration(days: kGraceDays)));

/// Decides whether a cafe's staff may use the POS.
///
/// The same policy is enforced server-side in firestore.rules
/// (function `cafeOperational`) so it cannot be bypassed from the app:
///   - cafe status must be "active"
///   - subscription status must not be "expired" or "suspended"
///   - subscription expiry date (if set) plus the grace period must be in
///     the future
/// Data is never deleted when access is blocked.
CafeAccess evaluateCafeAccess(Map<String, dynamic> cafe, DateTime now) {
  final name = (cafe['name'] ?? 'This cafe').toString();
  final status = (cafe['status'] ?? CafeStatus.active).toString();

  if (status == CafeStatus.deleted) {
    return CafeAccess(CafeAccessState.blocked,
        title: '$name has been closed', message: 'This cafe account is no longer active. Please contact the administrator.');
  }
  if (status == CafeStatus.suspended) {
    return CafeAccess(CafeAccessState.blocked,
        title: '$name is suspended', message: 'Access has been paused by the administrator. Your data is safe.');
  }
  if (status != CafeStatus.active) {
    return CafeAccess(CafeAccessState.blocked,
        title: '$name is inactive', message: 'This cafe is currently inactive. Please contact the administrator.');
  }
  if (cafe['legacyData'] == true) {
    return CafeAccess(CafeAccessState.migrating,
        title: '$name is being upgraded', message: 'Your cafe data is being moved to the new system. Please try again shortly.');
  }

  final sub = cafe['subscription'];
  if (sub is! Map) return const CafeAccess(CafeAccessState.allowed);

  final subStatus = (sub['status'] ?? SubscriptionStatus.active).toString();
  final expiry = Fmt.toDate(sub['expiryDate']);

  if (subStatus == SubscriptionStatus.suspended) {
    return CafeAccess(CafeAccessState.blocked,
        title: 'Subscription suspended', message: 'The POS subscription for $name is suspended. Your data is safe. Please contact the administrator.');
  }

  CafeAccess expired() => CafeAccess(CafeAccessState.blocked,
      title: 'Subscription expired',
      message: 'The POS subscription for $name expired${expiry != null ? ' on ${Fmt.date(expiry)}' : ''}. '
          'Your data is safe. Please renew to continue using the POS.',
      canRenew: true);

  if (subStatus == SubscriptionStatus.expired) return expired();
  if (expiry != null && !expiry.isAfter(now)) {
    final graceEnd = graceEndFor(expiry);
    if (!now.isBefore(graceEnd)) return expired();
    return CafeAccess(CafeAccessState.grace,
        title: 'Subscription expired',
        message: 'Subscription expired on ${Fmt.date(expiry)}. The POS stops on ${Fmt.dateTime(graceEnd)} – please renew now.',
        canRenew: true);
  }

  if (expiry != null) {
    final daysLeft = expiry.difference(now).inHours / 24;
    if (daysLeft <= kExpiryWarningDays) {
      final d = daysLeft.ceil();
      return CafeAccess(CafeAccessState.allowedWithWarning,
          message: 'Subscription expires ${d <= 1 ? 'within a day' : 'in $d days'} (${Fmt.date(expiry)}). Please renew to avoid interruption.',
          canRenew: true);
    }
  }
  if (subStatus == SubscriptionStatus.cancelled) {
    return CafeAccess(CafeAccessState.allowedWithWarning,
        message: 'Subscription cancelled${expiry != null ? ' – the POS works until ${Fmt.date(expiry)}' : ''}. Please contact the administrator to renew.');
  }
  if (subStatus == SubscriptionStatus.pending) {
    return const CafeAccess(CafeAccessState.allowedWithWarning,
        message: 'Subscription payment is pending. Please pay to keep using the POS.', canRenew: true);
  }
  if (subStatus == SubscriptionStatus.trial && expiry != null) {
    return CafeAccess(CafeAccessState.allowed, message: 'Trial until ${Fmt.date(expiry)}');
  }
  return const CafeAccess(CafeAccessState.allowed);
}
