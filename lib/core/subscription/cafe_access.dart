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
  static const all = [trial, active, pending, expired, suspended];
}

enum CafeAccessState {
  /// POS fully usable.
  allowed,

  /// Usable, but show a warning banner (expiring soon / payment pending).
  allowedWithWarning,

  /// Data still in the old global collections — waiting for migration.
  migrating,

  /// POS blocked; data is kept.
  blocked,
}

class CafeAccess {
  const CafeAccess(this.state, {this.title = '', this.message = ''});

  final CafeAccessState state;
  final String title;
  final String message;

  bool get canUsePos => state == CafeAccessState.allowed || state == CafeAccessState.allowedWithWarning;
}

/// Days before expiry at which staff start seeing a reminder.
const int kExpiryWarningDays = 7;

/// Decides whether a cafe's staff may use the POS.
///
/// The same policy is enforced server-side in firestore.rules
/// (function `cafeOperational`) so it cannot be bypassed from the app:
///   - cafe status must be "active"
///   - subscription status must not be "expired" or "suspended"
///   - subscription expiry date (if set) must be in the future
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
  if (subStatus == SubscriptionStatus.expired || (expiry != null && !expiry.isAfter(now))) {
    return CafeAccess(CafeAccessState.blocked,
        title: 'Subscription expired',
        message: 'The POS subscription for $name expired${expiry != null ? ' on ${Fmt.date(expiry)}' : ''}. '
            'Your data is safe. Please renew to continue using the POS.');
  }

  if (expiry != null) {
    final daysLeft = expiry.difference(now).inHours / 24;
    if (daysLeft <= kExpiryWarningDays) {
      final d = daysLeft.ceil();
      return CafeAccess(CafeAccessState.allowedWithWarning,
          message: 'Subscription expires ${d <= 1 ? 'within a day' : 'in $d days'} (${Fmt.date(expiry)}). Please renew to avoid interruption.');
    }
  }
  if (subStatus == SubscriptionStatus.pending) {
    return const CafeAccess(CafeAccessState.allowedWithWarning, message: 'Subscription payment is pending. Please contact the administrator.');
  }
  if (subStatus == SubscriptionStatus.trial && expiry != null) {
    return CafeAccess(CafeAccessState.allowed, message: 'Trial until ${Fmt.date(expiry)}');
  }
  return const CafeAccess(CafeAccessState.allowed);
}
