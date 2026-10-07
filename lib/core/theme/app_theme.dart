import 'package:flutter/material.dart';

/// Vocation SL design tokens.
///
/// Brand: the logo's leaf green and ink black. Surfaces stay quiet and white
/// so job content and company colours carry the page.
class AppColors {
  static const brandGreen = Color(0xFF7DB43A); // logo green, used for accents
  static const green = Color(0xFF3F7A1F); // accessible green for text/buttons on white
  static const greenDark = Color(0xFF2C5A14);
  static const greenTint = Color(0xFFEFF6E6);
  static const ink = Color(0xFF14171A);

  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF6F7F4);
  static const border = Color(0xFFE5E8E1);
  static const muted = Color(0xFF656C64);

  static const darkBg = Color(0xFF0F1210);
  static const darkSurface = Color(0xFF181C19);
  static const darkSurface2 = Color(0xFF212622);
  static const darkBorder = Color(0xFF2C322D);
  static const darkMuted = Color(0xFF9AA298);
  static const darkGreen = Color(0xFF9BCF5C);

  // Semantic
  static const info = Color(0xFF2F6FD1);
  static const warning = Color(0xFFC77A0A);
  static const danger = Color(0xFFC83A3A);
  static const success = Color(0xFF2E8B57);
  static const purple = Color(0xFF7A4CC2);
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const gutter = 20.0;
  static const radius = 16.0;
  static const radiusSm = 12.0;
  static const maxContentWidth = 1100.0;
  static const maxReadingWidth = 760.0;
}

/// Extra colours that Material's ColorScheme has no slot for.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.surface, required this.border, required this.muted, required this.accentTint, required this.shadow});

  final Color surface;
  final Color border;
  final Color muted;
  final Color accentTint;
  final Color shadow;

  static const light = AppPalette(
    surface: AppColors.surface,
    border: AppColors.border,
    muted: AppColors.muted,
    accentTint: AppColors.greenTint,
    shadow: Color(0x14000000),
  );

  static const dark = AppPalette(
    surface: AppColors.darkSurface,
    border: AppColors.darkBorder,
    muted: AppColors.darkMuted,
    accentTint: Color(0xFF1E2A17),
    shadow: Color(0x40000000),
  );

  @override
  AppPalette copyWith({Color? surface, Color? border, Color? muted, Color? accentTint, Color? shadow}) => AppPalette(
        surface: surface ?? this.surface,
        border: border ?? this.border,
        muted: muted ?? this.muted,
        accentTint: accentTint ?? this.accentTint,
        shadow: shadow ?? this.shadow,
      );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  bool get isWide => MediaQuery.sizeOf(this).width >= 840;
  bool get isTablet => MediaQuery.sizeOf(this).width >= 600;
}

class AppTheme {
  static const _font = 'PlusJakartaSans';

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: AppColors.green,
          onPrimary: Colors.white,
          primaryContainer: AppColors.greenTint,
          onPrimaryContainer: AppColors.greenDark,
          secondary: AppColors.ink,
          onSecondary: Colors.white,
          tertiary: AppColors.brandGreen,
          surface: AppColors.bg,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.muted,
          surfaceContainerHighest: AppColors.surface,
          outline: AppColors.border,
          outlineVariant: AppColors.border,
          error: AppColors.danger,
        ),
        palette: AppPalette.light,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: AppColors.darkGreen,
          onPrimary: Color(0xFF10200A),
          primaryContainer: Color(0xFF1E2A17),
          onPrimaryContainer: AppColors.darkGreen,
          secondary: Color(0xFFE8ECE6),
          onSecondary: AppColors.ink,
          tertiary: AppColors.brandGreen,
          surface: AppColors.darkBg,
          onSurface: Color(0xFFEDF0EB),
          onSurfaceVariant: AppColors.darkMuted,
          surfaceContainerHighest: AppColors.darkSurface2,
          outline: AppColors.darkBorder,
          outlineVariant: AppColors.darkBorder,
          error: Color(0xFFFF8A80),
        ),
        palette: AppPalette.dark,
      );

  static ThemeData _build({required Brightness brightness, required ColorScheme scheme, required AppPalette palette}) {
    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme, fontFamily: _font);
    final t = base.textTheme;
    final textTheme = t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1),
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.2),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: t.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.5),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm));

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      extensions: [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: palette.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: rounded,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: rounded,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.25)),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: textTheme.labelLarge)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide(color: palette.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide(color: palette.border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide(color: scheme.primary, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide(color: scheme.error)),
        hintStyle: TextStyle(color: palette.muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => textTheme.labelSmall?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.onSurface : palette.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : palette.muted),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: palette.muted),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: palette.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: palette.muted,
        indicatorColor: scheme.onSurface,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.titleSmall,
        dividerColor: palette.border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
      ),
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        ...base.pageTransitionsTheme.builders,
        TargetPlatform.android: const FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
