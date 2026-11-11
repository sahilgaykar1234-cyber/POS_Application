import 'package:flutter/material.dart';

/// "Ember" design tokens. Every screen reads colours through
/// `context.palette` so light and dark themes switch everything at once.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.primary,
    required this.primaryHover,
    required this.primaryTint,
    required this.onPrimary,
    required this.success,
    required this.successTint,
    required this.warning,
    required this.warningTint,
    required this.danger,
    required this.dangerTint,
    required this.info,
    required this.infoTint,
    required this.violet,
    required this.violetTint,
  });

  final Color canvas; // page background
  final Color surface; // cards, sheets
  final Color surfaceAlt; // subtle fills, table headers
  final Color border;
  final Color borderStrong; // input borders
  final Color ink; // main text
  final Color inkMuted; // secondary text (passes 4.5:1)
  final Color inkSubtle; // captions on surface (passes 4.5:1)
  final Color primary;
  final Color primaryHover;
  final Color primaryTint;
  final Color onPrimary;
  final Color success, successTint;
  final Color warning, warningTint;
  final Color danger, dangerTint;
  final Color info, infoTint;
  final Color violet, violetTint; // virtual tables

  static const light = Palette(
    canvas: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF2F4F7),
    border: Color(0xFFE4E7EC),
    borderStrong: Color(0xFFD0D5DD),
    ink: Color(0xFF101828),
    inkMuted: Color(0xFF344054),
    inkSubtle: Color(0xFF475467),
    primary: Color(0xFFC2410C),
    primaryHover: Color(0xFF9A3412),
    primaryTint: Color(0xFFFFF1E8),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF067647),
    successTint: Color(0xFFECFDF3),
    warning: Color(0xFFB54708),
    warningTint: Color(0xFFFFFAEB),
    danger: Color(0xFFB42318),
    dangerTint: Color(0xFFFEF3F2),
    info: Color(0xFF175CD3),
    infoTint: Color(0xFFEFF8FF),
    violet: Color(0xFF6927DA),
    violetTint: Color(0xFFF4F3FF),
  );

  static const dark = Palette(
    canvas: Color(0xFF0B0F14),
    surface: Color(0xFF12171E),
    surfaceAlt: Color(0xFF1A212B),
    border: Color(0xFF1F2733),
    borderStrong: Color(0xFF2E3A49),
    ink: Color(0xFFF2F4F7),
    inkMuted: Color(0xFFD0D5DD),
    inkSubtle: Color(0xFF98A2B3),
    primary: Color(0xFFF97316),
    primaryHover: Color(0xFFFB923C),
    primaryTint: Color(0xFF2A1A10),
    onPrimary: Color(0xFF1A0E05),
    success: Color(0xFF4ADE80),
    successTint: Color(0xFF0E2A1B),
    warning: Color(0xFFFBBF24),
    warningTint: Color(0xFF2A2210),
    danger: Color(0xFFF87171),
    dangerTint: Color(0xFF2E1414),
    info: Color(0xFF60A5FA),
    infoTint: Color(0xFF0F1F36),
    violet: Color(0xFFA78BFA),
    violetTint: Color(0xFF1E1734),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkSubtle: l(inkSubtle, other.inkSubtle),
      primary: l(primary, other.primary),
      primaryHover: l(primaryHover, other.primaryHover),
      primaryTint: l(primaryTint, other.primaryTint),
      onPrimary: l(onPrimary, other.onPrimary),
      success: l(success, other.success),
      successTint: l(successTint, other.successTint),
      warning: l(warning, other.warning),
      warningTint: l(warningTint, other.warningTint),
      danger: l(danger, other.danger),
      dangerTint: l(dangerTint, other.dangerTint),
      info: l(info, other.info),
      infoTint: l(infoTint, other.infoTint),
      violet: l(violet, other.violet),
      violetTint: l(violetTint, other.violetTint),
    );
  }
}

/// Spacing scale (4-pt grid).
class Space {
  Space._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
}

/// Corner radii.
class Radii {
  Radii._();
  static const double control = 8, card = 12, sheet = 16, pill = 999;
  static final BorderRadius controlR = BorderRadius.circular(control);
  static final BorderRadius cardR = BorderRadius.circular(card);
  static final BorderRadius sheetR = BorderRadius.circular(sheet);
}

/// Minimum touch target.
const double kTouch = 44;

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.light;
  TextTheme get text => Theme.of(this).textTheme;
}
