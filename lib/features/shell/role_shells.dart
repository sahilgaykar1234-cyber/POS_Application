import 'package:flutter/material.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_service.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/layout/app_shell.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses.dart';
import '../kitchen/kitchen_screen.dart';
import '../manager/manager_home_screen.dart';
import '../menu/menu_management_screen.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';
import '../orders/orders_board_screen.dart';
import '../pos/pos_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/business_settings.dart';
import '../settings/settings_screen.dart';
import '../staff/staff_management_screen.dart';

/// Keeps every page that has been opened alive (so a half-built order or a
/// scrolled list survives switching sections) but only builds a page the
/// first time it is visited.
class _LazyStack extends StatefulWidget {
  const _LazyStack({required this.index, required this.builders});
  final int index;
  final List<WidgetBuilder> builders;

  @override
  State<_LazyStack> createState() => _LazyStackState();
}

class _LazyStackState extends State<_LazyStack> {
  final _built = <int>{};

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          _built.contains(i) ? widget.builders[i](context) : const SizedBox.shrink(),
      ],
    );
  }
}

Future<void> _confirmSignOut(BuildContext context) async {
  final ok = await showConfirmDialog(context, title: 'Sign out?', message: 'You will need your username and password to sign in again.', confirmLabel: 'Sign out');
  if (ok && context.mounted) await signOutToLogin(context);
}

/// Running orders count for the Tables badge.
Stream<int> _runningCount() => OrderService.instance.watchAll().map((l) => todaysOrders(l).where((o) => o.isActive).length);

class _ShellFrame extends StatelessWidget {
  const _ShellFrame({
    required this.roleLabel,
    required this.destinations,
    required this.index,
    required this.onSelect,
    required this.builders,
    this.onSwitchMode,
    this.switchLabel,
  });

  final String roleLabel;
  final List<ShellDestination> Function(int running) destinations;
  final int index;
  final ValueChanged<int> onSelect;
  final List<WidgetBuilder> builders;
  final VoidCallback? onSwitchMode;
  final String? switchLabel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessSettings>(
      stream: BusinessSettingsRepository.instance.watch(),
      builder: (context, s) => StreamBuilder<int>(
        stream: _runningCount(),
        builder: (context, running) {
          final name = s.data?.shopName ?? '';
          return AppShell(
            brandTitle: name.isEmpty ? 'My Cafe' : name,
            brandSubtitle: roleLabel,
            destinations: destinations(running.data ?? 0),
            selectedIndex: index,
            onSelect: onSelect,
            onLogout: () => _confirmSignOut(context),
            actions: [
              if (onSwitchMode != null)
                TextButton.icon(onPressed: onSwitchMode, icon: const Icon(Icons.swap_horiz_rounded, size: 18), label: Text(switchLabel ?? 'Switch')),
            ],
            body: _LazyStack(index: index, builders: builders),
          );
        },
      ),
    );
  }
}

// =============================================================================

class ManagerShell extends StatefulWidget {
  const ManagerShell({super.key, this.onSwitchMode});
  final VoidCallback? onSwitchMode;

  @override
  State<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends State<ManagerShell> {
  int _i = 0;

  static const _pos = 1, _tables = 2;

  void _go(int i) => setState(() => _i = i);

  @override
  Widget build(BuildContext context) {
    final cafeId = FirestorePaths.activeCafeId;
    final me = AuthService.instance.currentUser;
    return _ShellFrame(
      roleLabel: 'Manager',
      index: _i,
      onSelect: _go,
      onSwitchMode: widget.onSwitchMode,
      switchLabel: 'Captain view',
      destinations: (running) => [
        const ShellDestination(icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard, label: 'Dashboard', onMobileBar: true),
        const ShellDestination(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: 'New order', onMobileBar: true),
        ShellDestination(icon: Icons.table_restaurant_outlined, selectedIcon: Icons.table_restaurant, label: 'Tables', badge: running, onMobileBar: true),
        const ShellDestination(icon: Icons.soup_kitchen_outlined, selectedIcon: Icons.soup_kitchen, label: 'Kitchen'),
        const ShellDestination(icon: Icons.restaurant_menu_outlined, selectedIcon: Icons.restaurant_menu, label: 'Menu', section: 'Manage', onMobileBar: true),
        const ShellDestination(icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'Reports'),
        const ShellDestination(icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet, label: 'Expenses'),
        const ShellDestination(icon: Icons.groups_outlined, selectedIcon: Icons.groups, label: 'Customers'),
        const ShellDestination(icon: Icons.badge_outlined, selectedIcon: Icons.badge, label: 'Staff'),
        const ShellDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
      ],
      builders: [
        (_) => ManagerHomeScreen(onNewOrder: () => _go(_pos), onOpenTables: () => _go(_tables)),
        (_) => PosScreen(onDone: () {}),
        (_) => const OrdersBoardScreen(canDelete: true),
        (_) => const KitchenScreen(),
        (_) => MenuManagementScreen(cafeId: cafeId),
        (_) => const ReportsScreen(),
        (_) => const ExpensesScreen(),
        (_) => const CustomersScreen(),
        (_) => StaffManagementScreen(cafeId: cafeId, cafeName: me?.displayName ?? 'My Cafe', embedded: true),
        (_) => const SettingsScreen(),
      ],
    );
  }
}

class CaptainShell extends StatefulWidget {
  const CaptainShell({super.key, this.onSwitchMode});
  final VoidCallback? onSwitchMode;

  @override
  State<CaptainShell> createState() => _CaptainShellState();
}

class _CaptainShellState extends State<CaptainShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return _ShellFrame(
      roleLabel: 'Captain',
      index: _i,
      onSelect: (i) => setState(() => _i = i),
      onSwitchMode: widget.onSwitchMode,
      switchLabel: 'Manager view',
      destinations: (running) => [
        const ShellDestination(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: 'New order', onMobileBar: true),
        ShellDestination(icon: Icons.table_restaurant_outlined, selectedIcon: Icons.table_restaurant, label: 'Tables', badge: running, onMobileBar: true),
        const ShellDestination(icon: Icons.soup_kitchen_outlined, selectedIcon: Icons.soup_kitchen, label: 'Kitchen', onMobileBar: true),
      ],
      builders: [
        (_) => PosScreen(onDone: () {}),
        (_) => const OrdersBoardScreen(canDelete: false),
        (_) => const KitchenScreen(),
      ],
    );
  }
}
