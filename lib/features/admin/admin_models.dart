import '../../core/subscription/cafe_access.dart';
import '../../core/utils/business_day.dart';
import '../../core/utils/formatters.dart';

/// Super Admin data models and pure calculations (unit-tested). Nothing here
/// invents numbers: every figure comes from cafes, users, plans and recorded
/// subscription payments.

// ------------------------------------------------------------------- cafe --

class CafeSummary {
  CafeSummary(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;

  String _s(String k) => (data[k] ?? '').toString().trim();

  String get name => _s('name').isEmpty ? 'Unnamed cafe' : _s('name');
  String get status => _s('status').isEmpty ? CafeStatus.active : _s('status');
  String get ownerName => _s('ownerName');
  String get ownerEmail => _s('ownerEmail');
  String get contactNumber => _s('contactNumber');
  String get address => _s('address');
  String get city => _s('city');
  String get state => _s('state');
  String get country => _s('country');
  String get gstNumber => _s('gstNumber');
  bool get legacyData => data['legacyData'] == true;
  DateTime? get createdAt => Fmt.toDate(data['createdAt']);
  DateTime? get updatedAt => Fmt.toDate(data['updatedAt']);

  String get location => [city, state, country].where((s) => s.isNotEmpty).join(', ');

  Map<String, dynamic> get subscription =>
      data['subscription'] is Map ? Map<String, dynamic>.from(data['subscription'] as Map) : const {};
  bool get hasSubscription => subscription.isNotEmpty && subscription['status'] != null;
  String? get planId => subscription['planId']?.toString();
  String? get planName => subscription['planName']?.toString();
  String get billingCycle => (subscription['billingCycle'] ?? '').toString();
  String get subscriptionStatus => (subscription['status'] ?? '').toString();
  DateTime? get expiryDate => Fmt.toDate(subscription['expiryDate']);
  DateTime? get startDate => Fmt.toDate(subscription['startDate']);
  double get amount => (subscription['amount'] is num) ? (subscription['amount'] as num).toDouble() : 0;
  String get paymentStatus => (subscription['paymentStatus'] ?? '').toString();

  bool get isDeleted => status == CafeStatus.deleted;
  bool get isActive => status == CafeStatus.active;

  /// Effective subscription state today: what the cafe actually experiences.
  SubState subState(DateTime now) {
    if (!hasSubscription) return SubState.none;
    final st = subscriptionStatus;
    final expired = expiryDate != null && !expiryDate!.isAfter(now);
    if (st == SubscriptionStatus.suspended) return SubState.suspended;
    if (st == SubscriptionStatus.expired || expired) return SubState.expired;
    if (st == SubscriptionStatus.cancelled) return SubState.cancelled;
    if (st == SubscriptionStatus.trial) return SubState.trial;
    if (st == SubscriptionStatus.pending) return SubState.pending;
    return SubState.active;
  }

  int? daysLeft(DateTime now) => expiryDate == null ? null : (expiryDate!.difference(now).inHours / 24).ceil();

  CafeAccess access(DateTime now) => evaluateCafeAccess(data, now);
}

enum SubState {
  none('No plan'),
  trial('Trial'),
  active('Active'),
  pending('Payment pending'),
  cancelled('Cancelled'),
  expired('Expired'),
  suspended('Suspended');

  const SubState(this.label);
  final String label;

  /// Still running (the cafe can use the POS on its subscription).
  bool get running => this == trial || this == active || this == pending || this == cancelled;
}

// ------------------------------------------------------------------- plans --

enum PlanTier {
  trial('Free Trial'),
  basic('Basic'),
  standard('Standard'),
  premium('Premium'),
  custom('Custom');

  const PlanTier(this.label);
  final String label;

  static PlanTier parse(Object? v) => PlanTier.values.where((t) => t.name == v).firstOrNull ?? PlanTier.custom;
}

class SubscriptionPlan {
  SubscriptionPlan(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  double? _n(String k) => data[k] is num ? (data[k] as num).toDouble() : null;
  int? _i(String k) => data[k] is num ? (data[k] as num).toInt() : null;

  String get name => (data['name'] ?? '').toString();
  PlanTier get tier => PlanTier.parse(data['tier']);
  String get description => (data['description'] ?? '').toString();
  bool get isActive => data['isActive'] != false;

  /// Older plans had one price + billing cycle; read them as monthly/yearly.
  double get monthlyPrice => _n('monthlyPrice') ?? (data['billingCycle'] == 'yearly' ? 0 : (_n('price') ?? 0));
  double get yearlyPrice => _n('yearlyPrice') ?? (data['billingCycle'] == 'yearly' ? (_n('price') ?? 0) : 0);
  int get trialDays => _i('trialDays') ?? (tier == PlanTier.trial ? (_i('durationDays') ?? 14) : 0);
  int? get maxStaff => _i('maxStaff');
  int? get maxDevices => _i('maxDevices');
  List<String> get features => ((data['features'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();

  bool get isFree => tier == PlanTier.trial || (monthlyPrice == 0 && yearlyPrice == 0);

  String get priceLabel {
    if (tier == PlanTier.trial) return 'Free · $trialDays days';
    final parts = [
      if (monthlyPrice > 0) '${Fmt.money(monthlyPrice)}/mo',
      if (yearlyPrice > 0) '${Fmt.money(yearlyPrice)}/yr',
    ];
    return parts.isEmpty ? 'Free' : parts.join(' · ');
  }
}

// -------------------------------------------------------------- payments --

class SubscriptionPayment {
  SubscriptionPayment(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get cafeId => (data['cafeId'] ?? '').toString();
  String get cafeName => (data['cafeName'] ?? '').toString();
  String get receiptNo => (data['receiptNo'] ?? '').toString();
  double get amount => (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0;
  String get method => (data['method'] ?? '').toString();
  String get referenceId => (data['referenceId'] ?? '').toString();
  String get notes => (data['notes'] ?? '').toString();
  String get planName => (data['planName'] ?? '').toString();

  /// Recorded payments are money received; "refunded" if reversed later.
  String get status => (data['status'] ?? 'received').toString();
  DateTime? get paidAt => Fmt.toDate(data['paidAt']);
  DateTime? get periodStart => Fmt.toDate(data['periodStart']);
  DateTime? get periodEnd => Fmt.toDate(data['periodEnd']);
}

const paymentMethods = ['UPI', 'Cash', 'Bank Transfer', 'Card', 'Cheque', 'Other'];

// ------------------------------------------------------------------ staff --

class StaffMember {
  StaffMember(this.uid, this.data);
  final String uid;
  final Map<String, dynamic> data;

  String get email => (data['email'] ?? '').toString();
  String get role => (data['role'] ?? '').toString();
  String? get cafeId => data['cafeId']?.toString();
  String get status => (data['status'] ?? 'active').toString();
  bool get isActive => status != 'disabled';
  DateTime? get updatedAt => Fmt.toDate(data['updatedAt']);

  /// Username logins are `name@pos.example.com`.
  bool get isUsernameLogin => email.endsWith('@pos.example.com');
  String get loginName => isUsernameLogin ? email.split('@').first : email;

  /// Shared cafe logins pick Manager or Captain view after signing in.
  bool get isSharedCafeLogin => isUsernameLogin && role == 'manager';

  String get displayName {
    final d = (data['displayName'] ?? '').toString().trim();
    return d.isEmpty ? loginName : d;
  }

  String get roleLabel => switch (role) {
        'superAdmin' => 'Super Admin',
        'manager' => isSharedCafeLogin ? 'Cafe login (Manager + Captain)' : 'Manager',
        'captain' => 'Captain',
        _ => 'No role',
      };
}

// --------------------------------------------------------------- platform --

class PlatformSettings {
  PlatformSettings(this.data);
  final Map<String, dynamic> data;

  static final empty = PlatformSettings(const {});

  String get platformName => (data['platformName'] ?? 'Cafe POS').toString();
  String get supportEmail => (data['supportEmail'] ?? '').toString();
  String get supportPhone => (data['supportPhone'] ?? '').toString();
  int get trialDays => data['trialDays'] is num ? (data['trialDays'] as num).toInt() : 14;
  String? get defaultPlanId => data['defaultPlanId']?.toString();
  int get reminderDays => data['reminderDays'] is num ? (data['reminderDays'] as num).toInt() : kExpiryWarningDays;

  /// Business-day end time new cafes start with ("05:00").
  int get defaultDayEndsAt => BusinessDay.parse(data['defaultDayEndsAt']) ?? BusinessDay.defaultCutoffMinutes;
  bool get alertNewCafes => data['alertNewCafes'] != false;
  bool get alertExpiring => data['alertExpiring'] != false;
  bool get alertPayments => data['alertPayments'] != false;
}

// ------------------------------------------------------------ dashboard --

class PlatformStats {
  PlatformStats({
    required this.totalCafes,
    required this.activeCafes,
    required this.inactiveCafes,
    required this.trialCafes,
    required this.managers,
    required this.captains,
    required this.activeSubscriptions,
    required this.expiredSubscriptions,
    required this.mrr,
    required this.hasRevenueData,
    required this.totalCollected,
    required this.paymentCount,
    required this.bySubState,
  });

  final int totalCafes, activeCafes, inactiveCafes, trialCafes, managers, captains;
  final int activeSubscriptions, expiredSubscriptions, paymentCount;

  /// Monthly recurring revenue from running paid subscriptions (yearly / 12).
  final double mrr;

  /// False when no subscription has an amount: MRR is then shown as "—".
  final bool hasRevenueData;
  final double totalCollected;
  final Map<SubState, int> bySubState;

  static PlatformStats of({
    required List<CafeSummary> cafes,
    required List<StaffMember> staff,
    required List<SubscriptionPayment> payments,
    required DateTime now,
  }) {
    final live = cafes.where((c) => !c.isDeleted).toList();
    final by = {for (final s in SubState.values) s: 0};
    var mrr = 0.0;
    var hasRevenue = false;
    for (final c in live) {
      final st = c.subState(now);
      by[st] = by[st]! + 1;
      if (st.running && st != SubState.trial && c.amount > 0) {
        hasRevenue = true;
        mrr += c.billingCycle == 'yearly' ? c.amount / 12 : c.amount;
      }
    }
    final received = payments.where((p) => p.status != 'refunded');
    return PlatformStats(
      totalCafes: live.length,
      activeCafes: live.where((c) => c.isActive).length,
      inactiveCafes: live.where((c) => !c.isActive).length,
      trialCafes: by[SubState.trial]!,
      managers: staff.where((s) => s.role == 'manager' && s.isActive).length,
      captains: staff.where((s) => s.role == 'captain' && s.isActive).length,
      activeSubscriptions: by[SubState.active]! + by[SubState.pending]! + by[SubState.cancelled]!,
      expiredSubscriptions: by[SubState.expired]!,
      mrr: mrr,
      hasRevenueData: hasRevenue,
      totalCollected: received.fold(0.0, (t, p) => t + p.amount),
      paymentCount: received.length,
      bySubState: by,
    );
  }
}

/// Count per month for the last [months] months (oldest first), e.g. cafes
/// onboarded or revenue collected.
List<(DateTime, double)> monthlySeries<T>(
  Iterable<T> items, {
  required DateTime? Function(T) dateOf,
  double Function(T)? valueOf,
  required DateTime now,
  int months = 6,
}) {
  final out = <(DateTime, double)>[];
  for (var i = months - 1; i >= 0; i--) {
    final start = DateTime(now.year, now.month - i);
    final end = DateTime(now.year, now.month - i + 1);
    var v = 0.0;
    for (final it in items) {
      final d = dateOf(it);
      if (d != null && !d.isBefore(start) && d.isBefore(end)) v += valueOf == null ? 1 : valueOf(it);
    }
    out.add((start, v));
  }
  return out;
}

// ----------------------------------------------------------------- alerts --

enum AlertLevel { critical, warning, info }

class AdminAlert {
  const AdminAlert(this.level, this.title, this.message, {this.cafeId, this.at});
  final AlertLevel level;
  final String title;
  final String message;
  final String? cafeId;
  final DateTime? at;
}

/// Things that need the Super Admin's attention, worked out from live data
/// (no stored or invented notifications). Most urgent first.
List<AdminAlert> computeAlerts({
  required List<CafeSummary> cafes,
  required List<StaffMember> staff,
  required DateTime now,
  PlatformSettings? settings,
}) {
  final s = settings ?? PlatformSettings.empty;
  final out = <AdminAlert>[];
  for (final c in cafes.where((c) => !c.isDeleted)) {
    final st = c.subState(now);
    final left = c.daysLeft(now);
    if (st == SubState.expired && c.isActive) {
      out.add(AdminAlert(AlertLevel.critical, '${c.name}: subscription expired',
          'Expired${c.expiryDate != null ? ' on ${Fmt.date(c.expiryDate)}' : ''}. The POS is blocked until it is renewed.',
          cafeId: c.id, at: c.expiryDate));
    } else if (st == SubState.suspended && c.isActive) {
      out.add(AdminAlert(AlertLevel.critical, '${c.name}: subscription suspended', 'The POS is blocked for this cafe.', cafeId: c.id));
    } else if (s.alertExpiring && st.running && left != null && left <= s.reminderDays) {
      out.add(AdminAlert(AlertLevel.warning, '${c.name}: ${st == SubState.trial ? 'trial' : 'subscription'} ends ${left <= 1 ? 'within a day' : 'in $left days'}',
          'Expires on ${Fmt.date(c.expiryDate)}.${st == SubState.cancelled ? ' It is cancelled and will not renew.' : ''}',
          cafeId: c.id, at: c.expiryDate));
    }
    if (s.alertPayments && st == SubState.pending) {
      out.add(AdminAlert(AlertLevel.warning, '${c.name}: payment pending', 'Record the payment when it is received.', cafeId: c.id));
    }
    if (!c.isActive) {
      out.add(AdminAlert(AlertLevel.info, '${c.name} is ${c.status}', 'Staff of this cafe cannot use the POS.', cafeId: c.id, at: c.updatedAt));
    }
    if (st == SubState.none && c.isActive) {
      out.add(AdminAlert(AlertLevel.info, '${c.name}: no plan assigned', 'Assign a plan or trial to track this cafe\'s subscription.', cafeId: c.id));
    }
    if (c.isActive && !staff.any((m) => m.cafeId == c.id && m.isActive)) {
      out.add(AdminAlert(AlertLevel.warning, '${c.name}: no login', 'Nobody can sign in to this cafe yet.', cafeId: c.id));
    }
    if (s.alertNewCafes && c.createdAt != null && now.difference(c.createdAt!).inDays < 7) {
      out.add(AdminAlert(AlertLevel.info, 'New cafe: ${c.name}', 'Registered on ${Fmt.date(c.createdAt)}.', cafeId: c.id, at: c.createdAt));
    }
  }
  out.sort((a, b) => a.level.index.compareTo(b.level.index));
  return out;
}

// ------------------------------------------------------------------ audit --

/// Human text for an audit entry's action.
String auditLabel(String action) => switch (action) {
      'cafe.create' => 'Cafe created',
      'cafe.update' => 'Cafe details updated',
      'cafe.status' => 'Cafe status changed',
      'cafe.delete' => 'Cafe deleted',
      'plan.create' => 'Plan created',
      'plan.update' => 'Plan updated',
      'subscription.set' => 'Subscription assigned',
      'subscription.renew' => 'Subscription renewed',
      'subscription.cancel' => 'Subscription cancelled',
      'payment.record' => 'Payment recorded',
      'staff.access' => 'Staff access changed',
      'platform.settings' => 'Platform settings changed',
      'migration.run' => 'Data migration',
      _ => action,
    };

// ------------------------------------------------------ recommended plans --

/// Starter plans for this POS (features are what the app really does today).
/// Prices are suggestions; edit them any time. Limits are informational: the
/// app does not block extra logins/devices.
const List<Map<String, Object?>> recommendedPlans = [
  {
    'name': 'Free Trial',
    'tier': 'trial',
    'monthlyPrice': 0,
    'yearlyPrice': 0,
    'trialDays': 14,
    'maxStaff': null,
    'maxDevices': null,
    'description': 'Try everything for 14 days.',
    'features': ['All features of Standard', 'No card needed', 'Data stays when you upgrade'],
  },
  {
    'name': 'Basic',
    'tier': 'basic',
    'monthlyPrice': 499,
    'yearlyPrice': 4999,
    'trialDays': 0,
    'maxStaff': 2,
    'maxDevices': 2,
    'description': 'For a small cafe or takeaway counter.',
    'features': [
      'POS billing with GST and discounts',
      'Tables and takeaway tokens',
      'Menu with sizes, prices and add-ons',
      'Sequential bill numbers',
      'Print receipt and WhatsApp bill',
      'Daily sales dashboard',
    ],
  },
  {
    'name': 'Standard',
    'tier': 'standard',
    'monthlyPrice': 899,
    'yearlyPrice': 8999,
    'trialDays': 0,
    'maxStaff': 5,
    'maxDevices': 4,
    'description': 'For a busy cafe with a kitchen team.',
    'features': [
      'Everything in Basic',
      'Kitchen screen with new-order alerts',
      'Extra (off-menu) items on bills',
      'Reports and CSV export',
      'Customer directory',
      'Orders history: view, print, share, edit',
      'Business day past midnight',
    ],
  },
  {
    'name': 'Premium',
    'tier': 'premium',
    'monthlyPrice': 1499,
    'yearlyPrice': 14999,
    'trialDays': 0,
    'maxStaff': null,
    'maxDevices': null,
    'description': 'For high-volume cafes that want hands-on help.',
    'features': [
      'Everything in Standard',
      'Unlimited logins and devices',
      'Menu setup done for you',
      'Logo and receipt branding setup',
      'Priority support',
    ],
  },
];

/// Recommended plans not created yet (matched by name, case-insensitive).
List<Map<String, Object?>> missingRecommendedPlans(List<SubscriptionPlan> existing) {
  final have = {for (final p in existing) p.name.trim().toLowerCase()};
  return [for (final p in recommendedPlans) if (!have.contains((p['name'] as String).toLowerCase())) p];
}
