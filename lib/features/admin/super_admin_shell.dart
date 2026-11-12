import 'package:flutter/material.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/layout/app_shell.dart';
import '../../core/widgets/confirm_dialog.dart';
import 'admin_dashboard_screen.dart';
import 'admin_data.dart';
import 'admin_service.dart';
import 'alerts_activity_screens.dart';
import 'cafes_screen.dart';
import 'payments_screen.dart';
import 'platform_settings_screen.dart';
import 'staff_screen.dart';
import 'subscriptions_screen.dart';

/// The Super Admin panel (only reached when the server-verified role is
/// superAdmin; firestore.rules enforce the same on every read and write).
class SuperAdminShell extends StatefulWidget {
  const SuperAdminShell({super.key, this.controller});

  /// Tests pass fixed data; the app listens to Firestore.
  final AdminDataController? controller;

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  late final AdminDataController _data = widget.controller ?? (AdminDataController()..start());
  int _i = 0;
  final Set<int> _built = {0};

  @override
  void dispose() {
    if (widget.controller == null) _data.dispose();
    super.dispose();
  }

  void _go(int i) => setState(() {
    _i = i;
    _built.add(i);
  });

  Future<void> _logout() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need your email and password to sign in again.',
      confirmLabel: 'Sign out',
    );
    if (ok && mounted) await signOutToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final screens = <WidgetBuilder>[
      (_) => AdminDashboardScreen(data: _data, onNavigate: _go),
      (_) => CafesScreen(data: _data),
      (_) => StaffScreen(data: _data),
      (_) => SubscriptionsScreen(data: _data),
      (_) => PaymentsScreen(data: _data),
      (_) => AlertsScreen(data: _data),
      (_) => ActivityScreen(data: _data),
      (_) => PlatformSettingsScreen(data: _data),
    ];
    return ValueListenableBuilder<AdminData>(
      valueListenable: _data,
      builder: (context, d, _) {
        final urgent = computeAlerts(cafes: d.cafes, staff: d.staff, now: DateTime.now(), settings: d.settings).where((a) => a.level != AlertLevel.info).length;
        return AppShell(
          brandTitle: d.settings.platformName,
          brandSubtitle: 'Super Admin',
          brandInitial: d.settings.platformName.isEmpty ? 'C' : d.settings.platformName[0],
          selectedIndex: _i,
          onSelect: _go,
          onLogout: _logout,
          destinations: [
            const ShellDestination(icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard, label: 'Dashboard', onMobileBar: true),
            ShellDestination(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront, label: 'Cafes', section: 'Manage', onMobileBar: true),
            const ShellDestination(icon: Icons.badge_outlined, selectedIcon: Icons.badge, label: 'Staff'),
            ShellDestination(
              icon: Icons.workspace_premium_outlined,
              selectedIcon: Icons.workspace_premium,
              label: 'Subscriptions',
              section: 'Billing',
              onMobileBar: true,
            ),
            const ShellDestination(icon: Icons.payments_outlined, selectedIcon: Icons.payments, label: 'Payments'),
            ShellDestination(
              icon: Icons.notifications_outlined,
              selectedIcon: Icons.notifications,
              label: 'Alerts',
              section: 'Monitor',
              badge: urgent,
              onMobileBar: true,
            ),
            const ShellDestination(icon: Icons.history_rounded, selectedIcon: Icons.history, label: 'Activity'),
            const ShellDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings', section: 'Platform'),
          ],
          body: IndexedStack(
            index: _i,
            children: [for (var i = 0; i < screens.length; i++) _built.contains(i) ? screens[i](context) : const SizedBox.shrink()],
          ),
        );
      },
    );
  }
}

/// Kept for callers that only need the service.
AdminService get adminService => AdminService.instance;
