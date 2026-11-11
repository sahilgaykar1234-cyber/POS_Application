import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'breakpoints.dart';

class ShellDestination {
  const ShellDestination({
    required this.icon,
    required this.label,
    IconData? selectedIcon,
    this.section,
    this.badge,
    this.onMobileBar = false,
  }) : selectedIcon = selectedIcon ?? icon;

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Small heading shown above this item in the sidebar.
  final String? section;
  final int? badge;

  /// Shown in the phone bottom bar (max 4; the rest go under "More").
  final bool onMobileBar;
}

/// Responsive app frame:
///  - desktop ≥1024: fixed sidebar + top bar
///  - tablet 600–1023: compact rail + top bar
///  - phone <600: top bar + bottom bar (+ "More" sheet)
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.brandTitle,
    required this.brandSubtitle,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.body,
    required this.onLogout,
    this.actions = const [],
    this.floatingActionButton,
    this.brandInitial,
  });

  final String brandTitle;
  final String brandSubtitle;
  final String? brandInitial;
  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final VoidCallback onLogout;

  String get _title => destinations[selectedIndex].label;

  @override
  Widget build(BuildContext context) {
    final size = context.screenSize;
    final p = context.palette;

    if (size == ScreenSize.mobile) return _mobile(context);

    final side = size == ScreenSize.desktop ? _Sidebar(shell: this) : _Rail(shell: this);
    return Scaffold(
      backgroundColor: p.canvas,
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          side,
          VerticalDivider(width: 1, color: p.border),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: _title, actions: actions),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    final p = context.palette;
    final barIdx = <int>[
      for (var i = 0; i < destinations.length; i++)
        if (destinations[i].onMobileBar) i,
    ].take(4).toList();
    final hasMore = barIdx.length < destinations.length;
    final selectedOnBar = barIdx.indexOf(selectedIndex);
    final navSelected = selectedOnBar >= 0 ? selectedOnBar : (hasMore ? barIdx.length : 0);

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: Text(_title), actions: [...actions, const SizedBox(width: 4)]),
      floatingActionButton: floatingActionButton,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i < barIdx.length) {
            onSelect(barIdx[i]);
          } else {
            _showMore(context, barIdx);
          }
        },
        destinations: [
          for (final i in barIdx)
            NavigationDestination(
              icon: _badge(context, destinations[i].badge, Icon(destinations[i].icon)),
              selectedIcon: _badge(context, destinations[i].badge, Icon(destinations[i].selectedIcon)),
              label: destinations[i].label,
            ),
          if (hasMore) const NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'More'),
        ],
      ),
    );
  }

  void _showMore(BuildContext context, List<int> onBar) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final p = ctx.palette;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BrandHeader(title: brandTitle, subtitle: brandSubtitle, initial: brandInitial),
                const SizedBox(height: Space.sm),
                for (var i = 0; i < destinations.length; i++)
                  if (!onBar.contains(i))
                    ListTile(
                      minTileHeight: 52,
                      leading: Icon(destinations[i].icon),
                      title: Text(destinations[i].label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      selected: i == selectedIndex,
                      selectedColor: p.primary,
                      selectedTileColor: p.primaryTint,
                      onTap: () {
                        Navigator.pop(ctx);
                        onSelect(i);
                      },
                    ),
                Divider(height: Space.xl, color: p.border),
                _ThemeTile(),
                ListTile(
                  minTileHeight: 52,
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onLogout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _badge(BuildContext context, int? n, Widget child) {
    if (n == null || n <= 0) return child;
    return Badge(label: Text('$n'), backgroundColor: context.palette.danger, child: child);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.actions});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: context.text.titleLarge, overflow: TextOverflow.ellipsis),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.title, required this.subtitle, this.initial, this.compact = false});
  final String title;
  final String subtitle;
  final String? initial;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final avatar = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Text(
        (initial ?? (title.isEmpty ? '?' : title[0])).toUpperCase(),
        style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w800, fontSize: 18),
      ),
    );
    if (compact) return Tooltip(message: '$title · $subtitle', child: avatar);
    return Row(
      children: [
        avatar,
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
              Text(subtitle, style: context.text.bodySmall?.copyWith(color: p.inkSubtle)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.shell});
  final AppShell shell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = <Widget>[];
    for (var i = 0; i < shell.destinations.length; i++) {
      final d = shell.destinations[i];
      if (d.section != null) {
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, Space.lg, 12, Space.xs),
            child: Text(d.section!.toUpperCase(), style: context.text.labelSmall?.copyWith(color: p.inkSubtle, letterSpacing: 0.8)),
          ),
        );
      }
      final selected = i == shell.selectedIndex;
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: selected ? p.primaryTint : Colors.transparent,
            borderRadius: Radii.controlR,
            child: InkWell(
              borderRadius: Radii.controlR,
              onTap: () => shell.onSelect(i),
              child: SizedBox(
                height: kTouch,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(selected ? d.selectedIcon : d.icon, size: 20, color: selected ? p.primary : p.inkSubtle),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        d.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? p.primaryHover : p.inkMuted,
                        ),
                      ),
                    ),
                    if ((d.badge ?? 0) > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: p.warningTint, borderRadius: BorderRadius.circular(Radii.pill)),
                        child: Text(
                          '${d.badge}',
                          style: TextStyle(color: p.warning, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: p.surface,
      child: SizedBox(
        width: 248,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.md),
                child: _BrandHeader(title: shell.brandTitle, subtitle: shell.brandSubtitle, initial: shell.brandInitial),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  children: items,
                ),
              ),
              Divider(color: p.border),
              Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Column(
                  children: [
                    _ThemeTile(),
                    ListTile(
                      minTileHeight: kTouch,
                      leading: const Icon(Icons.logout_rounded, size: 20),
                      title: Text(
                        'Sign out',
                        style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500),
                      ),
                      onTap: shell.onLogout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.shell});
  final AppShell shell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
              child: _BrandHeader(title: shell.brandTitle, subtitle: shell.brandSubtitle, initial: shell.brandInitial, compact: true),
            ),
            Expanded(
              child: NavigationRail(
                selectedIndex: shell.selectedIndex,
                onDestinationSelected: shell.onSelect,
                labelType: NavigationRailLabelType.all,
                minWidth: 88,
                destinations: [
                  for (final d in shell.destinations)
                    NavigationRailDestination(
                      icon: AppShell._badge(context, d.badge, Icon(d.icon)),
                      selectedIcon: AppShell._badge(context, d.badge, Icon(d.selectedIcon)),
                      label: Text(d.label, textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Light / dark',
              onPressed: () => ThemeController.instance.toggle(context),
              icon: Icon(ThemeController.instance.isDark(context) ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: shell.onLogout,
              icon: Icon(Icons.logout_rounded, color: p.inkSubtle),
            ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark(context);
    return ListTile(
      minTileHeight: kTouch,
      leading: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20),
      title: Text(
        dark ? 'Light mode' : 'Dark mode',
        style: TextStyle(color: context.palette.inkMuted, fontWeight: FontWeight.w500),
      ),
      onTap: () => ThemeController.instance.toggle(context),
    );
  }
}
