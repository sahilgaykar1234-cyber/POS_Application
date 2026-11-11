import 'package:flutter/material.dart';

import 'tokens.dart';

/// Legacy dark colours, used only by the (on-hold) Super Admin screens, which
/// keep their previous look via [AppTheme.legacyAdmin].
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF141211);
  static const Color surface = Color(0xFF1E1A17);
  static const Color surfaceAlt = Color(0xFF231E1B);
  static const Color border = Color(0xFF2C2520);

  static const Color primary = Color(0xFFE65C00);
  static const Color accent = Color(0xFFF7B731);

  static const Color success = Colors.green;
  static const Color danger = Colors.redAccent;
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Inter';

  static ThemeData light() => _build(Palette.light, Brightness.light);
  static ThemeData dark() => _build(Palette.dark, Brightness.dark);

  /// The previous dark brown theme (Super Admin screens only).
  static ThemeData get legacyAdmin => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(primary: AppColors.primary, secondary: AppColors.accent, surface: AppColors.surface),
    fontFamily: fontFamily,
    useMaterial3: true,
    extensions: const [Palette.dark],
  );

  static ThemeData _build(Palette p, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primaryTint,
      onPrimaryContainer: p.primaryHover,
      secondary: p.ink,
      onSecondary: p.surface,
      error: p.danger,
      onError: p.onPrimary,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.inkSubtle,
      surfaceContainerHighest: p.surfaceAlt,
      surfaceContainerHigh: p.surfaceAlt,
      surfaceContainer: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainerLowest: p.surface,
      outline: p.borderStrong,
      outlineVariant: p.border,
    );

    final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: fontFamily);
    final text = base.textTheme
        .copyWith(
          displaySmall: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6),
          headlineMedium: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          headlineSmall: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
          titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          bodyLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        )
        .apply(bodyColor: p.ink, displayColor: p.ink, fontFamily: fontFamily);

    final controlShape = RoundedRectangleBorder(borderRadius: Radii.controlR);
    const minSize = Size(64, kTouch);
    const btnText = TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600);

    OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: Radii.controlR,
      borderSide: BorderSide(color: c, width: w),
    );

    return base.copyWith(
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      dividerColor: p.border,
      extensions: [p],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        shape: Border(bottom: BorderSide(color: p.border)),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardR,
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          minimumSize: minSize,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: controlShape,
          textStyle: btnText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          elevation: 0,
          minimumSize: minSize,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: controlShape,
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.inkMuted,
          side: BorderSide(color: p.borderStrong),
          minimumSize: minSize,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: controlShape,
          textStyle: btnText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          minimumSize: const Size(48, kTouch),
          shape: controlShape,
          textStyle: btnText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.inkMuted, minimumSize: const Size(kTouch, kTouch)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        extendedTextStyle: btnText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: ob(p.borderStrong),
        enabledBorder: ob(p.borderStrong),
        focusedBorder: ob(p.primary, 2),
        errorBorder: ob(p.danger),
        focusedErrorBorder: ob(p.danger, 2),
        disabledBorder: ob(p.border),
        labelStyle: TextStyle(fontFamily: fontFamily, color: p.inkSubtle, fontSize: 14),
        floatingLabelStyle: TextStyle(fontFamily: fontFamily, color: p.primary, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(fontFamily: fontFamily, color: p.inkSubtle),
        prefixIconColor: p.inkSubtle,
        suffixIconColor: p.inkSubtle,
        errorStyle: TextStyle(fontFamily: fontFamily, color: p.danger, fontSize: 12, fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.ink,
        disabledColor: p.surfaceAlt,
        labelStyle: TextStyle(fontFamily: fontFamily, color: p.inkMuted, fontWeight: FontWeight.w500, fontSize: 13),
        secondaryLabelStyle: TextStyle(fontFamily: fontFamily, color: p.surface, fontWeight: FontWeight.w600, fontSize: 13),
        side: BorderSide(color: p.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.sheetR),
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        showDragHandle: true,
        dragHandleColor: p.borderStrong,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: TextStyle(fontFamily: fontFamily, color: p.surface, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: Radii.controlR),
        width: 420,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primaryTint,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? p.primary : p.inkSubtle,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.primary : p.inkSubtle)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.primaryTint,
        selectedIconTheme: IconThemeData(color: p.primary),
        unselectedIconTheme: IconThemeData(color: p.inkSubtle),
        selectedLabelTextStyle: TextStyle(fontFamily: fontFamily, color: p.primary, fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(fontFamily: fontFamily, color: p.inkSubtle, fontSize: 12),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.inkSubtle,
        indicatorColor: p.primary,
        dividerColor: p.border,
        labelStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.surface : p.surface),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.success : p.borderStrong),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : Colors.transparent),
        side: BorderSide(color: p.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          selectedBackgroundColor: p.ink,
          selectedForegroundColor: p.surface,
          foregroundColor: p.inkMuted,
          side: BorderSide(color: p.borderStrong),
          shape: controlShape,
          minimumSize: const Size(48, 40),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.inkSubtle,
        textColor: p.ink,
        subtitleTextStyle: TextStyle(fontFamily: fontFamily, color: p.inkSubtle, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: Radii.controlR),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.controlR,
          side: BorderSide(color: p.border),
        ),
        textStyle: TextStyle(fontFamily: fontFamily, color: p.ink, fontSize: 14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.surfaceAlt),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(6)),
        textStyle: TextStyle(fontFamily: fontFamily, color: p.surface, fontSize: 12),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
      datePickerTheme: DatePickerThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    );
  }
}
