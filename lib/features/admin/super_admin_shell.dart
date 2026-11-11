import 'package:flutter/material.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import 'activity_tab.dart';
import 'admin_dashboard_tab.dart';
import 'cafes_tab.dart';
import 'payments_tab.dart';
import 'plans_tab.dart';

/// Master Admin panel: separate navigation from the cafe staff screens.
class SuperAdminShell extends StatefulWidget {
  const SuperAdminShell({super.key});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.storefront_outlined, Icons.storefront, 'Cafes'),
    (Icons.workspace_premium_outlined, Icons.workspace_premium, 'Plans'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Payments'),
    (Icons.history_outlined, Icons.history, 'Activity'),
  ];

  void goTo(int i) => setState(() => _index = i);

  Widget _body() => switch (_index) {
        0 => AdminDashboardTab(onNavigate: goTo),
        1 => const CafesTab(),
        2 => const PlansTab(),
        3 => const PaymentsTab(),
        _ => const ActivityTab(),
      };

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true && mounted) await signOutToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final appBar = AppBar(
      backgroundColor: AppColors.surface,
      titleSpacing: wide ? 16 : 12,
      title: Row(
        children: [
          const AppLogo(size: 30),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              wide ? '${AppConfig.appName} · Master Admin' : _destinations[_index].$3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent),
            ),
          ),
        ],
      ),
      actions: [
        if (wide && user != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text(user.email, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          ),
        IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: _confirmSignOut),
      ],
    );

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: AppColors.surface,
              selectedIndex: _index,
              onDestinationSelected: goTo,
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppColors.primary.withValues(alpha: 0.25),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: _body()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appBar,
      body: _body(),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        selectedIndex: _index,
        onDestinationSelected: goTo,
        indicatorColor: AppColors.primary.withValues(alpha: 0.25),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
