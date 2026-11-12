import 'package:flutter/material.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/config/app_config.dart';
import '../../core/layout/app_shell.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/web/favicon.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../customers/customers_screen.dart';
import '../kitchen/kitchen_screen.dart';
import '../kitchen/order_alerts_host.dart';
import '../manager/manager_home_screen.dart';
import '../menu/menu_management_screen.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';
import '../orders/orders_board_screen.dart';
import '../orders/orders_screen.dart';
import '../takeaway/takeaway_screen.dart';
import '../pos/pos_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/business_settings.dart';
import '../settings/settings_screen.dart';

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
/// Active orders today: (dine-in, takeaway) for the nav badges.
typedef _Counts = ({int dineIn, int takeaway});
Stream<_Counts> _runningCount() => OrderService.instance.watchLive().map((l) {
      final active = todaysOrders(l).where((o) => o.isActive);
      final take = active.where((o) => o.isTakeaway && o.tableNo.trim().isEmpty).length;
      return (dineIn: active.length - take, takeaway: take);
    });

/// Browser tab: cafe name + uploaded logo as favicon (web only).
Widget _brandTab({required BuildContext context, required BusinessSettings? settings, required Widget child}) {
  applyFavicon(settings?.logoBase64);
  final name = settings?.shopName ?? '';
  return Title(
    title: name.isEmpty ? AppConfig.appName : '$name · ${AppConfig.appName}',
    color: context.palette.primary,
    child: child,
  );
}

class _ShellFrame extends StatelessWidget {
  const _ShellFrame({
    required this.roleLabel,
    required this.destinations,
    required this.index,
    required this.onSelect,
    required this.builders,
    this.onSwitchMode,
    this.switchLabel,
    this.bottomNav = false,
  });

  final bool bottomNav;

  final String roleLabel;
  final List<ShellDestination> Function(_Counts running) destinations;
  final int index;
  final ValueChanged<int> onSelect;
  final List<WidgetBuilder> builders;
  final VoidCallback? onSwitchMode;
  final String? switchLabel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessSettings>(
      stream: BusinessSettingsRepository.instance.watch(),
      builder: (context, s) => StreamBuilder<_Counts>(
        stream: _runningCount(),
        initialData: (dineIn: 0, takeaway: 0),
        builder: (context, running) {
          final name = s.data?.shopName ?? '';
          return _brandTab(
            context: context,
            settings: s.data,
            child: AppShell(
              brandTitle: name.isEmpty ? 'My Cafe' : name,
              brandSubtitle: roleLabel,
              brandLogoBase64: s.data?.logoBase64,
              destinations: destinations(running.data ?? (dineIn: 0, takeaway: 0)),
              selectedIndex: index,
              onSelect: onSelect,
              onLogout: () => _confirmSignOut(context),
              actions: [
                if (onSwitchMode != null)
                  TextButton.icon(onPressed: onSwitchMode, icon: const Icon(Icons.swap_horiz_rounded, size: 18), label: Text(switchLabel ?? 'Switch')),
              ],
              bottomNav: bottomNav,
              body: _LazyStack(index: index, builders: builders),
            ),
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

  static const _tables = 1;
  static const _orders = 3;

  void _go(int i) => setState(() => _i = i);

  /// New orders open from Tables (tap a free table) or the dashboard button.
  void _newOrder() => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen(standalone: true)));

  @override
  Widget build(BuildContext context) {
    final cafeId = FirestorePaths.activeCafeId;
    return _ShellFrame(
      roleLabel: 'Manager',
      // Navigation at the bottom on every screen size (as in the original app).
      bottomNav: true,
      index: _i,
      onSelect: _go,
      onSwitchMode: widget.onSwitchMode,
      switchLabel: 'Captain view',
      destinations: (running) => [
        const ShellDestination(icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard, label: 'Dashboard', onMobileBar: true),
        ShellDestination(icon: Icons.table_restaurant_outlined, selectedIcon: Icons.table_restaurant, label: 'Tables', badge: running.dineIn, onMobileBar: true),
        ShellDestination(icon: Icons.shopping_bag_outlined, selectedIcon: Icons.shopping_bag, label: 'Takeaway', badge: running.takeaway, onMobileBar: true),
        const ShellDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'Orders'),
        const ShellDestination(icon: Icons.soup_kitchen_outlined, selectedIcon: Icons.soup_kitchen, label: 'Kitchen', onMobileBar: true),
        const ShellDestination(icon: Icons.restaurant_menu_outlined, selectedIcon: Icons.restaurant_menu, label: 'Menu', onMobileBar: true),
        const ShellDestination(icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'Reports'),
        const ShellDestination(icon: Icons.groups_outlined, selectedIcon: Icons.groups, label: 'Customers'),
        const ShellDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
      ],
      builders: [
        (_) => ManagerHomeScreen(onNewOrder: _newOrder, onOpenTables: () => _go(_tables), onOpenOrders: () => _go(_orders)),
        (_) => const OrdersBoardScreen(canDelete: true),
        (_) => const TakeawayScreen(),
        (_) => const OrdersScreen(),
        (_) => const KitchenScreen(),
        (_) => MenuManagementScreen(cafeId: cafeId),
        (_) => const ReportsScreen(),
        (_) => const CustomersScreen(),
        (_) => const SettingsScreen(),
      ],
    );
  }
}

/// Captain: only the kitchen board. Orders come from the Manager; the
/// Captain just moves them New → Preparing → Ready.
class CaptainShell extends StatelessWidget {
  const CaptainShell({super.key, this.onSwitchMode});
  final VoidCallback? onSwitchMode;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessSettings>(
      stream: BusinessSettingsRepository.instance.watch(),
      builder: (context, s) {
        final p = context.palette;
        final name = (s.data?.shopName ?? '').isEmpty ? 'My Cafe' : s.data!.shopName;
        final logo = decodeLogo(s.data?.logoBase64);
        final wide = !context.isMobile;
        return _brandTab(
          context: context,
          settings: s.data,
          child: Scaffold(
            backgroundColor: p.canvas,
            appBar: AppBar(
              titleSpacing: wide ? Space.xl : Space.lg,
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: logo == null ? p.primary : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: logo == null ? null : Border.all(color: p.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: logo != null
                        ? Image.memory(logo, fit: BoxFit.contain, gaplessPlayback: true)
                        : Text(name[0].toUpperCase(), style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('Captain · Kitchen', style: TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                if (onSwitchMode != null)
                  wide
                      ? TextButton.icon(onPressed: onSwitchMode, icon: const Icon(Icons.swap_horiz_rounded, size: 18), label: const Text('Manager view'))
                      : IconButton(tooltip: 'Manager view', onPressed: onSwitchMode, icon: const Icon(Icons.swap_horiz_rounded)),
                const SystemAlertsButton(),
                IconButton(tooltip: 'Sign out', onPressed: () => _confirmSignOut(context), icon: const Icon(Icons.logout_rounded)),
                const SizedBox(width: Space.sm),
              ],
            ),
            body: const OrderAlertsHost(child: KitchenScreen()),
          ),
        );
      },
    );
  }
}
