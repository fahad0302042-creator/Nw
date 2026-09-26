import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Selectable palettes. `trueBlack` is the default: pure #000000 backgrounds
/// so OLED pixels are physically off — it saves battery and, next to cover
/// art, makes the artwork the only thing emitting light.
enum AppPalette {
  trueBlack('Pure Black', Color(0xFF7C5CFF), Color(0xFF000000)),
  midnight('Midnight', Color(0xFF5B8CFF), Color(0xFF0B0D12)),
  graphite('Graphite', Color(0xFFE8E8EA), Color(0xFF0E0E0E)),
  matcha('Matcha', Color(0xFF34D399), Color(0xFF05100C)),
  sakura('Sakura', Color(0xFFFF6E9C), Color(0xFF14070C)),
  amber('Amber', Color(0xFFFFB020), Color(0xFF120D04)),
  paper('Paper (light)', Color(0xFF3B3B44), Color(0xFFFBFBF9));

  const AppPalette(this.label, this.accent, this.background);

  final String label;
  final Color accent;
  final Color background;

  bool get isLight => this == AppPalette.paper;
}

/// A restrained, OLED-first theme with iOS structural cues.
///
/// The iOS influence is deliberate and structural rather than cosmetic:
/// large collapsing titles, hairline (0.5px) separators instead of heavy
/// dividers, translucent chrome, generous 17pt-ish body text, and very low
/// colour saturation so covers carry the visual weight.
class AppTheme {
  /// Apple's hairline. On a 3x screen this lands on a single physical pixel.
  static const hairline = 0.5;

  static ThemeData build(AppPalette palette) {
    final light = palette.isLight;
    final bg = palette.background;
    final accent = palette.accent;

    final onBg = light ? const Color(0xFF16161A) : const Color(0xFFF2F2F5);
    final muted = light ? const Color(0xFF8A8A8E) : const Color(0xFF8A8A8E);

    // On a true-black theme the "elevated" surface must stay near-black or
    // the OLED benefit is lost; we lift by a few points only.
    final surface = light
        ? const Color(0xFFFFFFFF)
        : Color.alphaBlend(const Color(0x0DFFFFFF), bg);
    final surfaceHigh = light
        ? const Color(0xFFF1F1EE)
        : Color.alphaBlend(const Color(0x14FFFFFF), bg);
    final separator = light ? const Color(0x1F000000) : const Color(0x1FFFFFFF);

    final scheme = ColorScheme(
      brightness: light ? Brightness.light : Brightness.dark,
      primary: accent,
      onPrimary: light ? Colors.white : _contrastOn(accent),
      secondary: accent,
      onSecondary: _contrastOn(accent),
      surface: bg,
      onSurface: onBg,
      surfaceContainer: surface,
      surfaceContainerHighest: surfaceHigh,
      onSurfaceVariant: muted,
      outline: muted,
      outlineVariant: separator,
      error: const Color(0xFFFF453A),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: separator,
      splashFactory: InkSparkle.splashFactory,

      // iOS-weight typography: larger body text, tighter display tracking.
      textTheme: _textTheme(onBg, muted),

      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: onBg,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: separator,
        thickness: hairline,
        space: hairline,
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 58,
        backgroundColor: light ? const Color(0xF2FFFFFF) : const Color(0xF2000000),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: TextStyle(
          fontSize: 16,
          color: onBg,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: muted),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: onBg,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(fontSize: 12, color: onBg),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: TextStyle(color: muted, fontSize: 15),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearMinHeight: 2,
      ),

      // iOS-style horizontal slide instead of Android's vertical fade.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(Color onBg, Color muted) => TextTheme(
        headlineSmall: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: onBg,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: onBg,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: muted,
        ),
        bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: onBg),
        bodySmall: TextStyle(fontSize: 12.5, color: muted),
      );

  /// Picks black or white text for an accent chip so it always stays legible.
  static Color _contrastOn(Color c) =>
      c.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

/// iOS-style hairline separator.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) => Container(
        height: AppTheme.hairline,
        margin: EdgeInsets.only(left: indent),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

/// Translucent, blurred chrome — the frosted-glass effect iOS uses for
/// navigation bars, so content visibly scrolls underneath.
class FrostedBar extends StatelessWidget {
  const FrostedBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: ColoredBox(color: bg.withAlpha(200), child: child),
      ),
    );
  }
}
