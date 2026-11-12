import 'dart:async';

import 'package:flutter/foundation.dart';

import 'admin_service.dart';

/// Live platform data shared by every Super Admin screen (one listener per
/// collection for the whole panel).
class AdminData {
  const AdminData({
    this.cafes = const [],
    this.staff = const [],
    this.plans = const [],
    this.payments = const [],
    this.platform,
    this.loading = true,
    this.error,
  });

  final List<CafeSummary> cafes;
  final List<StaffMember> staff;
  final List<SubscriptionPlan> plans;
  final List<SubscriptionPayment> payments;
  final PlatformSettings? platform;
  final bool loading;
  final Object? error;

  PlatformSettings get settings => platform ?? PlatformSettings.empty;

  CafeSummary? cafe(String id) => cafes.where((c) => c.id == id).firstOrNull;
  String cafeName(String? id) => id == null ? '—' : (cafe(id)?.name ?? 'Unknown cafe');

  AdminData copyWith({
    List<CafeSummary>? cafes,
    List<StaffMember>? staff,
    List<SubscriptionPlan>? plans,
    List<SubscriptionPayment>? payments,
    PlatformSettings? platform,
    bool? loading,
    Object? error,
  }) =>
      AdminData(
        cafes: cafes ?? this.cafes,
        staff: staff ?? this.staff,
        plans: plans ?? this.plans,
        payments: payments ?? this.payments,
        platform: platform ?? this.platform,
        loading: loading ?? this.loading,
        error: error ?? this.error,
      );
}

class AdminDataController extends ValueNotifier<AdminData> {
  AdminDataController() : super(const AdminData());

  /// Fixed data (tests / previews).
  AdminDataController.fixed(super.data);

  final List<StreamSubscription> _subs = [];
  final Set<String> _received = {};

  void start() {
    final s = AdminService.instance;
    void got(String k, AdminData Function(AdminData) f) {
      _received.add(k);
      value = f(value).copyWith(loading: _received.length < 5);
    }

    void fail(Object e) => value = value.copyWith(error: e, loading: false);
    _subs.addAll([
      s.watchCafes().listen((v) => got('cafes', (d) => d.copyWith(cafes: v)), onError: fail),
      s.watchStaff().listen((v) => got('staff', (d) => d.copyWith(staff: v)), onError: fail),
      s.watchPlans().listen((v) => got('plans', (d) => d.copyWith(plans: v)), onError: fail),
      s.watchPayments().listen((v) => got('payments', (d) => d.copyWith(payments: v)), onError: fail),
      s.watchPlatformSettings().listen((v) => got('platform', (d) => d.copyWith(platform: v)), onError: fail),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
