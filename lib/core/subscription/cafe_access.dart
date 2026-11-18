import '../utils/business_day.dart';
import '../utils/formatters.dart';
import 'package:pos_app/core/i18n/tr.dart';

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
  const CafeAccess(this.state, {this.title = '', this.message = '', this.canRenew = false, this.daysLeft});

  final CafeAccessState state;
  final String title;
  final String message;

  /// Paying the subscription would fix this (expiring, pending, in grace or
  /// expired). False for a suspended / closed cafe: only the admin can help.
  final bool canRenew;

  /// Days until the expiry date, when it is inside the warning period.
  final int? daysLeft;

  /// The plan is ending or has just ended: remind the cafe to pay.
  bool get shouldRemindToPay => canRenew && (state == CafeAccessState.grace || daysLeft != null);

  bool get canUsePos =>
      state == CafeAccessState.allowed || state == CafeAccessState.allowedWithWarning || state == CafeAccessState.grace;
}

/// Days before expiry at which staff start seeing a reminder, when the Super
/// Admin's "Warn before expiry" setting has not reached this cafe yet.
const int kExpiryWarningDays = 7;

/// Days the POS keeps working after the expiry date, so a cafe is never cut
/// off in the middle of service and has time to pay.
const int kGraceDays = 3;

/// Whole calendar days from [now] to [expiry]: on 18 Nov, a plan ending any
/// time on 26 Nov has 8 days left.
int calendarDaysLeft(DateTime expiry, DateTime now) =>
    DateTime.utc(expiry.year, expiry.month, expiry.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

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
  final name = (cafe['name'] ?? tr('This cafe')).toString();
  final status = (cafe['status'] ?? CafeStatus.active).toString();

  if (status == CafeStatus.deleted) {
    return CafeAccess(CafeAccessState.blocked,
        title: tr('{0} has been closed', [name]), message: tr('This cafe account is no longer active. Please contact the administrator.'));
  }
  if (status == CafeStatus.suspended) {
    return CafeAccess(CafeAccessState.blocked,
        title: tr('{0} is suspended', [name]), message: tr('Access has been paused by the administrator. Your data is safe.'));
  }
  if (status != CafeStatus.active) {
    return CafeAccess(CafeAccessState.blocked,
        title: tr('{0} is inactive', [name]), message: tr('This cafe is currently inactive. Please contact the administrator.'));
  }
  if (cafe['legacyData'] == true) {
    return CafeAccess(CafeAccessState.migrating,
        title: tr('{0} is being upgraded', [name]), message: tr('Your cafe data is being moved to the new system. Please try again shortly.'));
  }

  final sub = cafe['subscription'];
  if (sub is! Map) return const CafeAccess(CafeAccessState.allowed);

  final subStatus = (sub['status'] ?? SubscriptionStatus.active).toString();
  final expiry = Fmt.toDate(sub['expiryDate']);

  if (subStatus == SubscriptionStatus.suspended) {
    return CafeAccess(CafeAccessState.blocked,
        title: tr('Subscription suspended'), message: tr('The POS subscription for {0} is suspended. Your data is safe. Please contact the administrator.', [name]));
  }

  CafeAccess expired() => CafeAccess(CafeAccessState.blocked,
      title: tr('Subscription expired'),
      message: tr('The POS subscription for {0} expired{1}. Your data is safe. Please renew to continue using the POS.',
          [name, expiry != null ? ' on ${Fmt.date(expiry)}' : '']),
      canRenew: true);

  if (subStatus == SubscriptionStatus.expired) return expired();
  if (expiry != null && !expiry.isAfter(now)) {
    final graceEnd = graceEndFor(expiry);
    if (!now.isBefore(graceEnd)) return expired();
    return CafeAccess(CafeAccessState.grace,
        title: tr('Subscription expired'),
        message: tr('Subscription expired on {0}. The POS stops on {1} – please renew now.', [Fmt.date(expiry), Fmt.dateTime(graceEnd)]),
        canRenew: true);
  }

  if (expiry != null) {
    // The Super Admin's "Warn before expiry" days, copied onto each cafe.
    final setting = cafe['reminderDays'];
    final warningDays = setting is num && setting >= 1 ? setting.toInt() : kExpiryWarningDays;
    final d = calendarDaysLeft(expiry, now);
    if (d <= warningDays) {
      return CafeAccess(CafeAccessState.allowedWithWarning,
          message: tr('Subscription expires {0} ({1}). Please renew to avoid interruption.', [d <= 1 ? tr('within a day') : tr('in {0} days', [d]), Fmt.date(expiry)]),
          canRenew: true,
          daysLeft: d);
    }
  }
  if (subStatus == SubscriptionStatus.cancelled) {
    return CafeAccess(CafeAccessState.allowedWithWarning,
        message: tr('Subscription cancelled{0}. Please contact the administrator to renew.', [expiry != null ? tr(' – the POS works until {0}', [Fmt.date(expiry)]) : '']));
  }
  if (subStatus == SubscriptionStatus.pending) {
    return CafeAccess(CafeAccessState.allowedWithWarning,
        message: tr('Subscription payment is pending. Please pay to keep using the POS.'), canRenew: true);
  }
  if (subStatus == SubscriptionStatus.trial && expiry != null) {
    return CafeAccess(CafeAccessState.allowed, message: tr('Trial until {0}', [Fmt.date(expiry)]));
  }
  return const CafeAccess(CafeAccessState.allowed);
}
