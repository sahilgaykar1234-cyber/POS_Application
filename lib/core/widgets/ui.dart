import 'package:flutter/material.dart';

import '../layout/breakpoints.dart';
import '../theme/tokens.dart';
import '../utils/formatters.dart';

/// Shared building blocks so every screen looks the same. All colours come
/// from the active theme's [Palette] (light or dark).

/// Page body with consistent padding and a max width on big screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1280, this.padding, this.bottomPadding = 96});

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets? padding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final pad = context.isMobile ? Space.lg : Space.xl;
    return ListView(
      padding: padding ?? EdgeInsets.fromLTRB(pad, pad, pad, bottomPadding),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// Title + subtitle + actions row at the top of a page.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: context.isMobile ? context.text.headlineSmall : context.text.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: p.inkSubtle)),
              ],
            ],
          ),
          if (actions.isNotEmpty) Wrap(spacing: Space.sm, runSpacing: Space.sm, children: actions),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
    this.caption,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final String? caption;

  /// Dark "hero" card (e.g. today's sales).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.primary;
    final bg = highlight ? p.ink : p.surface;
    final fg = highlight ? p.surface : p.ink;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: Radii.cardR, side: BorderSide(color: highlight ? bg : p.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: highlight ? p.border : p.inkSubtle)),
                  ),
                  Icon(icon, size: 18, color: highlight ? p.border : c),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    letterSpacing: -0.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: highlight ? p.border : c)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive grid of cards: 1–6 columns depending on width.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minTileWidth = 200, this.spacing = 12, this.maxColumns = 6});

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minTileWidth).floor().clamp(1, maxColumns);
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color, this.tint});
  final String label;
  final Color? color;
  final Color? tint;

  static (Color, Color) colorsFor(BuildContext context, String status) {
    final p = context.palette;
    return switch (status) {
      'active' || 'paid' || 'completed' || 'done' || 'free' || 'available' => (p.success, p.successTint),
      'trial' || 'preparing' || 'cooking' => (p.info, p.infoTint),
      'pending' || 'invited' || 'ready' || 'payment due' || 'ordered' => (p.warning, p.warningTint),
      'inactive' || 'none' => (p.inkSubtle, p.surfaceAlt),
      'virtual' => (p.violet, p.violetTint),
      'expired' || 'suspended' || 'deleted' || 'disabled' || 'overdue' || 'cancelled' || 'sold out' => (p.danger, p.dangerTint),
      _ => (p.inkSubtle, p.surfaceAlt),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (c, t) = colorsFor(context, label.toLowerCase());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: tint ?? t, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Text(label, style: TextStyle(color: color ?? c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.surfaceAlt, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: p.inkSubtle),
            ),
            const SizedBox(height: Space.lg),
            Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(message!, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: p.inkSubtle)),
            ],
            if (action != null) ...[const SizedBox(height: Space.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// Error placeholder with optional retry.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.message = 'Could not load data. Please check your internet connection.', this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        message: message,
        action: onRetry == null ? null : OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      );
}

/// Centered spinner.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            if (label != null) ...[
              const SizedBox(height: Space.md),
              Text(label!, style: TextStyle(color: context.palette.inkSubtle)),
            ],
          ],
        ),
      );
}

/// White (surface) card that hosts ListTiles/InkWells correctly (ripples
/// and tile colours paint on this Material).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.margin});
  final Widget child;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: Radii.cardR, side: BorderSide(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.icon, this.padding, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: Space.lg),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(Space.lg + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: p.inkSubtle), const SizedBox(width: Space.sm)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitle != null) Text(subtitle!, style: context.text.bodySmall?.copyWith(color: p.inkSubtle)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: Space.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Label/value row for detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: TextStyle(color: context.palette.inkSubtle))),
          Expanded(child: SelectableText(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

/// Money in tabular numerals (₹1,23,456).
class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, this.style, this.symbol = '₹'});
  final num amount;
  final TextStyle? style;
  final String symbol;

  @override
  Widget build(BuildContext context) => Text(
        Fmt.money(amount, symbol: symbol),
        style: (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      );
}

/// − qty + control with 44px targets.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.qty, required this.onChanged, this.filled = false});
  final int qty;
  final ValueChanged<int> onChanged;

  /// Solid primary style (used on item cards once added).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = filled ? p.onPrimary : p.ink;
    return Container(
      decoration: BoxDecoration(
        color: filled ? p.primary : p.surface,
        borderRadius: Radii.controlR,
        border: filled ? null : Border.all(color: p.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: kTouch,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Decrease',
              onPressed: () => onChanged(qty - 1),
              icon: Icon(qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, size: 20, color: fg),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          SizedBox(
            width: 40,
            height: kTouch,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Increase',
              onPressed: () => onChanged(qty + 1),
              icon: Icon(Icons.add_rounded, size: 20, color: filled ? fg : p.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search input with icon.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search', this.controller, this.width});
  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded, size: 20)),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Pill-shaped filter chips row (single select).
class FilterPills<T> extends StatelessWidget {
  const FilterPills({super.key, required this.options, required this.selected, required this.onSelected, this.scroll = true});
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chips = [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(right: Space.sm),
          child: ChoiceChip(
            label: Text(o.$2),
            selected: o.$1 == selected,
            onSelected: (_) => onSelected(o.$1),
            labelStyle: TextStyle(
              color: o.$1 == selected ? p.surface : p.inkMuted,
              fontWeight: o.$1 == selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
    ];
    if (!scroll) return Wrap(runSpacing: Space.sm, children: chips);
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips));
  }
}

void showSuccess(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(Icons.check_circle_rounded, color: context.palette.success, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
    ));

void showError(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(Icons.error_rounded, color: context.palette.danger, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
    ));

/// Date picker with app defaults.
Future<DateTime?> pickDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: first ?? DateTime(now.year - 5),
    lastDate: last ?? DateTime(now.year + 10),
  );
}
