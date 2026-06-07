import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'a11y.dart';

// ── Dark Futuristic Theme Colors ────────────────────────────────────────────
class ThemeColors {
  // Backgrounds
  final Color bg;
  final Color bg2;
  final Color bg3;

  // Accent
  final Color accent;
  final Color accentDim;
  final Color accentGlow;

  // Secondary Accents — color-coded sections
  final Color accent2;  // success / students
  final Color accent3;  // faculty / emerald
  final Color accentPink; // curriculum / purple
  final Color accentIndigo;
  final Color accentOrange; // inventory / gold

  // Semantic
  final Color danger;
  final Color warn;

  // Text
  final Color white;
  final Color text;
  final Color muted;

  // Borders & Glass
  final Color border;
  final Color glass;

  // Shadows
  final Color cardShadow;
  final Color glowShadow;

  // Subject tag colors
  final Color subjectTagBg;
  final Color subjectTagText;

  // Semester tag colors
  final Color semesterTagBg;
  final Color semesterTagText;

  // Gradients
  final LinearGradient accentGradient;
  final LinearGradient subtleGradient;
  final LinearGradient purpleGradient;
  final LinearGradient cardGradient;

  const ThemeColors({
    required this.bg,
    required this.bg2,
    required this.bg3,
    required this.accent,
    required this.accentDim,
    required this.accentGlow,
    required this.accent2,
    required this.accent3,
    required this.accentPink,
    required this.accentIndigo,
    required this.accentOrange,
    required this.danger,
    required this.warn,
    required this.white,
    required this.text,
    required this.muted,
    required this.border,
    required this.glass,
    required this.cardShadow,
    required this.glowShadow,
    required this.subjectTagBg,
    required this.subjectTagText,
    required this.semesterTagBg,
    required this.semesterTagText,
    required this.accentGradient,
    required this.subtleGradient,
    required this.purpleGradient,
    required this.cardGradient,
  });

  bool get isLight => bg.computeLuminance() > 0.5;
  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  /// Subtle ambient gradient across the full app background.
  /// Electric blue at top-left, deep violet at bottom-right — barely visible.
  LinearGradient get backgroundGradient => LinearGradient(
    colors: isLight
        ? [const Color(0xFF2C3E6B).withValues(alpha: 0.04), const Color(0xFFC62828).withValues(alpha: 0.03)]
        : [const Color(0xFF1E88E5).withValues(alpha: 0.06), const Color(0xFF8E24AA).withValues(alpha: 0.04)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── CSTIAN Dynamic Theme ───────────────────────────────────────────────────
  //   • Background: #0B111E deep dark luxury navy
  //   • Cards:      #0F1626 translucent dark navy tile
  //   • Primary:    #1E88E5 electric blue
  //   • Success:    #4CAF50 vibrant green
  //   • Warning:    #FF8F00 neon amber
  //   • Secondary:  #8E24AA deep violet
  //   • Danger:     #E53935 system red
  //   • Text:       #FFFFFF / #94A3B8
  //   • AccentText: #FFD700 soft metallic gold (use via GradientText)
  //   • Borders:    rgba(255,255,255,0.06)
  static const darkFuturistic = ThemeColors(
    bg: Color(0xFF0B111E),
    bg2: Color(0xFF0F1626),
    bg3: Color(0xFF131B2D),
    accent: Color(0xFF1E88E5),
    accentDim: Color(0xFF1565C0),
    accentGlow: Color(0x1A1E88E5),
    accent2: Color(0xFF4CAF50),
    accent3: Color(0xFF4CAF50),
    accentPink: Color(0xFF8E24AA),
    accentIndigo: Color(0xFF7B1FA2),
    accentOrange: Color(0xFFFF8F00),
    danger: Color(0xFFE53935),
    warn: Color(0xFFFF8F00),
    white: Color(0xFFFFFFFF),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFF94A3B8),
    border: Color(0x14FFFFFF), // white at ~8% alpha
    glass: Color(0xE60F1626),
    cardShadow: Color(0x40000000),
    glowShadow: Color(0x261E88E5),
    subjectTagBg: Color(0x331E88E5),
    subjectTagText: Color(0xFF1E88E5),
    semesterTagBg: Color(0x334CAF50),
    semesterTagText: Color(0xFF4CAF50),
    accentGradient: LinearGradient(
      colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    subtleGradient: LinearGradient(
      colors: [Color(0xFF0B111E), Color(0xFF0D1525)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    purpleGradient: LinearGradient(
      colors: [Color(0xFF8E24AA), Color(0xFFAB47BC)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardGradient: LinearGradient(
      colors: [Color(0xFF0F1626), Color(0xFF0C1320)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // Keep appleDark for backward compat — just alias to darkFuturistic
  static const appleDark = darkFuturistic;
  static const appleLight = lightCompat;
  static const googleMusicDark = darkFuturistic;
  static const light = lightCompat;

  // ── Dynamic / Material You — generated from a seed color ─────────────────
  /// Generates a full [ThemeColors] palette from a single [seed] color,
  /// using Material 3's [ColorScheme.fromSeed] color science so the result
  /// is always harmonious.
  ///
  /// When [brightness] is [Brightness.light], backgrounds stay warm ivory;
  /// when dark, they stay pure AMOLED black — only the accent / semantic
  /// colours are derived from the seed.
  static ThemeColors fromSeed({required Color seed, required Brightness brightness}) {
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final isLight = brightness == Brightness.light;

    return ThemeColors(
      bg: isLight ? const Color(0xFFF3EDE4) : const Color(0xFF000000),
      bg2: isLight ? const Color(0xFFFDFBF7) : const Color(0xFF050508),
      bg3: isLight ? const Color(0xFFEEE8DE) : const Color(0xFF0A0A10),
      accent: s.primary,
      accentDim: s.primaryContainer,
      accentGlow: s.primary.withValues(alpha: 0.1),
      accent2: s.secondary,
      accent3: s.tertiary,
      accentPink: s.tertiary,
      accentIndigo: Color.lerp(s.secondary, s.tertiary, 0.5)!,
      accentOrange: Color.lerp(s.tertiary, s.error, 0.2)!,
      danger: s.error,
      warn: isLight ? const Color(0xFFD47300) : const Color(0xFFFFA726),
      white: isLight ? const Color(0xFF1A1410) : const Color(0xFFFFFFFF),
      text: s.onSurface,
      muted: s.onSurfaceVariant,
      border: s.outlineVariant,
      glass: (isLight ? const Color(0xFFFDFBF7) : const Color(0xFF050508)).withValues(alpha: 0.9),
      cardShadow: s.shadow.withValues(alpha: isLight ? 0.15 : 0.25),
      glowShadow: s.primary.withValues(alpha: isLight ? 0.12 : 0.15),
      subjectTagBg: s.primary.withValues(alpha: 0.2),
      subjectTagText: s.primary,
      semesterTagBg: s.secondary.withValues(alpha: 0.2),
      semesterTagText: s.secondary,
      accentGradient: LinearGradient(
        colors: [s.primary, s.primaryContainer],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      subtleGradient: LinearGradient(
        colors: isLight
            ? [const Color(0xFFF3EDE4), const Color(0xFFF0E9DF)]
            : [const Color(0xFF000000), const Color(0xFF030306)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      purpleGradient: LinearGradient(
        colors: [s.tertiary, Color.lerp(s.tertiary, Colors.white, 0.2)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      cardGradient: isLight
          ? LinearGradient(
              colors: [const Color(0xFFFEFCF9), const Color(0xFFF9F3E8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : LinearGradient(
              colors: [
                Color.lerp(s.primary, const Color(0xFF000000), 0.85)!,
                const Color(0xFF060E1E),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
    );
  }

  // ── Warm Academic Theme (Light) ─────────────────────────────────────────
  //   • Background: #F8F4EE warm ivory (feels like premium paper)
  //   • Cards:      #FDFBF7 warm cream with subtle gradient & warm shadow
  //   • Primary:    #2C3E6B deep navy (professional, academic authority)
  //   • Students:   #1A7A5C deep teal
  //   • Faculty:    #2B6B4A deep forest green
  //   • Curriculum: #6B3FA0 deep violet
  //   • Inventory:  #B8860B dark goldenrod
  //   • Danger:     #C62828 deep crimson
  //   • Text:       #2C1810 warm brown-black (like ink on paper)
  //   • Muted:      #8B7355 warm taupe
  //   • Borders:    #D4C9B6 warm tan (like aged paper edges)
  // ── Warm Academic Theme (Light) — warmed accents ────────────────────────
  //   • Background: #F3EDE4 warm ivory (premium paper feel)
  //   • Cards:      #FDFBF7 warm cream with subtle gradient & warm shadow
  //   • Primary:    #2C3E6B deep navy (academic authority)
  //   • Students:   #2D7A55 warmer teal-green (sunlight-kissed)
  //   • Faculty:    #3D6B40 warmer forest green
  //   • Curriculum: #7B4FA0 warmer violet
  //   • Inventory:  #C4941A brighter gold
  //   • Danger:     #C62828 deep crimson
  //   • Text:       #2C1810 warm brown-black (ink on paper)
  //   • Muted:      #8B7355 warm taupe
  //   • Borders:    #D4C9B6 warm tan (aged paper edges)
  static const lightCompat = ThemeColors(
    bg: Color(0xFFF3EDE4),
    bg2: Color(0xFFFDFBF7),
    bg3: Color(0xFFEEE8DE),
    accent: Color(0xFF2C3E6B),
    accentDim: Color(0xFF1A2744),
    accentGlow: Color(0x1A4A3828),
    accent2: Color(0xFF2D7A55),
    accent3: Color(0xFF3D6B40),
    accentPink: Color(0xFF7B4FA0),
    accentIndigo: Color(0xFF5B4BD5),
    accentOrange: Color(0xFFC4941A),
    danger: Color(0xFFC62828),
    warn: Color(0xFFD47300),
    white: Color(0xFF1A1410),
    text: Color(0xFF2C1810),
    muted: Color(0xFF5C4D3A),
    border: Color(0xFFD4C9B6),
    glass: Color(0xE6FDFBF7),
    cardShadow: Color(0x282C1810),
    glowShadow: Color(0x204A3828),
    subjectTagBg: Color(0x332C3E6B),
    subjectTagText: Color(0xFF2C3E6B),
    semesterTagBg: Color(0x332D7A55),
    semesterTagText: Color(0xFF2D7A55),
    accentGradient: LinearGradient(
      colors: [Color(0xFF2C3E6B), Color(0xFF1A2744)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    subtleGradient: LinearGradient(
      colors: [Color(0xFFF3EDE4), Color(0xFFF0E9DF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    purpleGradient: LinearGradient(
      colors: [Color(0xFF7B4FA0), Color(0xFF9B6FD0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardGradient: LinearGradient(
      colors: [Color(0xFFFEFCF9), Color(0xFFF9F3E8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

// ── Build ThemeData ─────────────────────────────────────────────────────────
ThemeData buildThemeData(ThemeColors c) {
  final textTheme = _buildTextTheme(c);

  return ThemeData(
    useMaterial3: true,
    brightness: c.brightness,
    colorScheme: ColorScheme(
      brightness: c.brightness,
      primary: c.accent,
      onPrimary: Colors.white,
      primaryContainer: c.accentDim,
      onPrimaryContainer: Colors.white,
      secondary: c.accent2,
      onSecondary: Colors.white,
      secondaryContainer: c.semesterTagBg,
      onSecondaryContainer: c.semesterTagText,
      tertiary: c.accentPink,
      onTertiary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: c.bg,
      onSurface: c.text,
      surfaceContainerHighest: c.bg3,
      surfaceContainerHigh: c.bg3,
      surfaceContainer: c.bg2,
      surfaceContainerLow: c.bg,
      onSurfaceVariant: c.muted,
      outline: c.border,
      outlineVariant: c.border.withValues(alpha: 0.5),
      shadow: c.cardShadow,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: c.bg2,
    cardColor: c.bg2,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(
      color: c.border,
      thickness: 0.5,
    ),
    hoverColor: c.accent.withValues(alpha: 0.08),
    splashColor: c.accent.withValues(alpha: 0.12),
    highlightColor: c.accent.withValues(alpha: 0.06),

    // ── Typography ──
    textTheme: textTheme,
    primaryTextTheme: textTheme,

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      iconTheme: IconThemeData(color: c.white),
      actionsIconTheme: IconThemeData(color: c.white),
      titleTextStyle: GoogleFonts.rajdhani(
        textStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: c.white,
          fontSize: 18,
          letterSpacing: 0.5,
        ),
      ),
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    primaryIconTheme: IconThemeData(color: c.white),
    iconTheme: IconThemeData(color: c.white),

    // ── Cards: dark gradient, radius 16, subtle border, shadow ──
    cardTheme: CardThemeData(
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border, width: 0.5),
      ),
      margin: const EdgeInsets.all(0),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.bg3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.accent, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.danger.withValues(alpha: 0.6)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.danger, width: 2.0),
      ),
      errorStyle: GoogleFonts.dmSans(textStyle: TextStyle(color: c.danger, fontSize: 12)),
      labelStyle: GoogleFonts.dmSans(textStyle: TextStyle(color: c.muted, fontSize: 13)),
      hintStyle: GoogleFonts.dmSans(textStyle: TextStyle(color: c.muted.withValues(alpha: 0.7), fontSize: 13)),
      prefixIconColor: c.muted,
      suffixIconColor: c.muted,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: c.accent.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0,
          ),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent,
        side: BorderSide(color: c.accent.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: GoogleFonts.dmSans(
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0,
          ),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: GoogleFonts.dmSans(
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0,
          ),
        ),
      ),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.bg2,
      selectedItemColor: c.accent,
      unselectedItemColor: c.muted,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: GoogleFonts.dmSans(
        textStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      unselectedLabelStyle: GoogleFonts.dmSans(
        textStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: c.bg2,
      titleTextStyle: GoogleFonts.rajdhani(
        textStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: c.white,
          fontSize: 18,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border, width: 0.5),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.bg2,
      contentTextStyle: GoogleFonts.dmSans(
        textStyle: TextStyle(
          color: c.text,
          fontSize: 14,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border, width: 0.5),
      ),
      actionTextColor: c.accent,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.bg2,
      modalBackgroundColor: c.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: c.bg2,
      textStyle: GoogleFonts.dmSans(textStyle: TextStyle(color: c.text, fontSize: 13)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border, width: 0.5),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border, width: 0.5),
      ),
      textStyle: GoogleFonts.dmSans(
        textStyle: TextStyle(
          color: c.text,
          fontSize: 12,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: c.bg3,
      selectedColor: c.accent.withValues(alpha: 0.15),
      labelStyle: GoogleFonts.dmSans(textStyle: TextStyle(color: c.text, fontSize: 12)),
      side: BorderSide(color: c.border, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: c.accent,
      unselectedLabelColor: c.muted,
      indicatorColor: c.accent,
      dividerColor: c.border,
      labelStyle: GoogleFonts.rajdhani(
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0.3,
        ),
      ),
      unselectedLabelStyle: GoogleFonts.rajdhani(
        textStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 15,
          letterSpacing: 0.3,
        ),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: c.white,
      textColor: c.text,
      tileColor: Colors.transparent,
      titleTextStyle: GoogleFonts.dmSans(
        textStyle: TextStyle(
          color: c.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      subtitleTextStyle: GoogleFonts.dmSans(
        textStyle: TextStyle(
          color: c.muted,
          fontSize: 13,
          letterSpacing: 0,
        ),
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.accent;
        return c.muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return c.accent.withValues(alpha: 0.3);
        }
        return c.bg3;
      }),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: BorderSide(color: c.muted, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.accent;
        return c.muted;
      }),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.bg3,
      circularTrackColor: c.bg3,
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _SlideUpTransitionBuilder(),
        TargetPlatform.iOS: _CupertinoTransitionBuilder(),
      },
    ),
  );
}

/// Build text theme with the dark futuristic font stack:
///   • Exo 2 Bold — displays / numbers
///   • Rajdhani SemiBold — headings
///   • DM Sans Regular — body / labels
TextTheme _buildTextTheme(ThemeColors c) {
  return TextTheme(
    // Large Title — Exo 2 Bold
    displayLarge: GoogleFonts.exo2(
      textStyle: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: c.white,
        letterSpacing: 0,
      ),
    ),
    // Title 1 — Exo 2 Bold
    displayMedium: GoogleFonts.exo2(
      textStyle: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: c.white,
        letterSpacing: 0,
      ),
    ),
    // Title 2 — Rajdhani SemiBold
    displaySmall: GoogleFonts.rajdhani(
      textStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: c.white,
        letterSpacing: 0.3,
      ),
    ),
    // Title 3 — Rajdhani SemiBold
    headlineLarge: GoogleFonts.rajdhani(
      textStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: c.white,
        letterSpacing: 0.3,
      ),
    ),
    // Headline — Rajdhani SemiBold
    headlineMedium: GoogleFonts.rajdhani(
      textStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: c.white,
        letterSpacing: 0.3,
      ),
    ),
    // Body large — DM Sans
    headlineSmall: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: c.text,
        letterSpacing: 0,
      ),
    ),
    // Subhead — DM Sans
    titleLarge: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: c.text,
        letterSpacing: 0,
      ),
    ),
    // Footnote — DM Sans
    titleMedium: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: c.text,
        letterSpacing: 0,
      ),
    ),
    titleSmall: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c.text,
        letterSpacing: 0,
      ),
    ),
    bodyLarge: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: c.text,
        height: 1.5,
        letterSpacing: 0,
      ),
    ),
    bodyMedium: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: c.text,
        height: 1.5,
        letterSpacing: 0,
      ),
    ),
    bodySmall: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: c.muted,
        height: 1.4,
        letterSpacing: 0,
      ),
    ),
    // Caption — DM Sans
    labelLarge: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: c.text,
        letterSpacing: 0,
      ),
    ),
    labelMedium: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: c.muted,
        letterSpacing: 0,
      ),
    ),
    labelSmall: GoogleFonts.dmSans(
      textStyle: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        color: c.muted,
        letterSpacing: 0,
      ),
    ),
  ).apply(
    fontFamilyFallback: ['NotoColorEmoji'],
  );
}

/// Slide-up transition for Android
class _SlideUpTransitionBuilder extends PageTransitionsBuilder {
  const _SlideUpTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reducedMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// iOS-style push transition
class _CupertinoTransitionBuilder extends PageTransitionsBuilder {
  const _CupertinoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reducedMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInQuart,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}
