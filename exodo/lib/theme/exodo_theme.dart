import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ExodoColors {
  static const Color background = Color(0xFF0E0C0A); // Negro Cálido (fondo global dark)
  static const Color surface = Color(0xFF141414);    // Superficie tarjeta (Neutro puro sin marrón)
  static const Color border = Color(0xFF222222);     // Bordes sutiles (Neutro puro sin marrón)
  static const Color amber = Color(0xFFC9933A);      // Ámbar Éxodo (Exclusivo marca/acento)
  static const Color amberGlow = Color(0x33C9933A);  // Ámbar traslúcido para resplandores
  static const Color textPrimary = Color(0xFFF5F2EB);
  static const Color textSecondary = Color(0xFF9E9689);
  static const Color error = Color(0xFFE5534B);

  // === Dark mode: colores específicos por zona ===
  static const Color chatBg = Color(0xFF141414);         // Fondo del chat (donde va el saludo)
  static const Color composerBg = Color(0xFF1D1D1D);     // Tab/cápsula donde se escribe
  static const Color modelChipBg = Color(0xFF131313);    // Rectángulo selector de modelo
  static const Color tokenBarBg = Color(0xFF1D1D1D);     // Barra de progreso de tokens
}

class ExodoTheme {
  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: ExodoColors.background,
      primaryColor: ExodoColors.amber,
      colorScheme: const ColorScheme.dark(
        primary: ExodoColors.amber,
        secondary: ExodoColors.amber,
        surface: ExodoColors.surface,
        error: ExodoColors.error,
        onPrimary: ExodoColors.background,
        onSurface: ExodoColors.textPrimary,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.syne(color: ExodoColors.textPrimary, fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.syne(color: ExodoColors.textPrimary, fontWeight: FontWeight.bold),
        headlineLarge: GoogleFonts.syne(color: ExodoColors.textPrimary, fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.syne(color: ExodoColors.textPrimary, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.syne(color: ExodoColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 20),
        titleMedium: GoogleFonts.inter(color: ExodoColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: GoogleFonts.inter(color: ExodoColors.textPrimary, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: ExodoColors.textPrimary, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: ExodoColors.textSecondary, fontSize: 12),
        labelLarge: GoogleFonts.jetBrainsMono(color: ExodoColors.amber, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ExodoColors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: ExodoColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: ExodoColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: ExodoColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ExodoColors.surface,
        hintStyle: GoogleFonts.inter(color: ExodoColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: ExodoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: ExodoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: ExodoColors.amber),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light();
    const creamBg = Color(0xFFFBF9F5); // Blanco yeso o hueso cremoso
    const creamSurface = Color(0xFFF5F5F5);
    const darkInk = Color(0xFF171615);

    return base.copyWith(
      scaffoldBackgroundColor: creamBg,
      primaryColor: ExodoColors.amber,
      colorScheme: const ColorScheme.light(
        primary: ExodoColors.amber,
        secondary: ExodoColors.amber,
        surface: creamSurface,
        error: ExodoColors.error,
        onPrimary: creamBg,
        onSurface: darkInk,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.syne(color: darkInk, fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.syne(color: darkInk, fontWeight: FontWeight.bold),
        headlineLarge: GoogleFonts.syne(color: darkInk, fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.syne(color: darkInk, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.syne(color: darkInk, fontWeight: FontWeight.w600, fontSize: 20),
        titleMedium: GoogleFonts.inter(color: darkInk, fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: GoogleFonts.inter(color: darkInk, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: darkInk, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: const Color(0xFF7B7872), fontSize: 12),
        labelLarge: GoogleFonts.jetBrainsMono(color: ExodoColors.amber, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: creamBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkInk),
      ),
    );
  }
}
