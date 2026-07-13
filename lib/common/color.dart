import 'dart:math';

import 'package:flutter/material.dart';

extension ColorExtension on Color {
  Color get opacity80 {
    return withAlpha(204);
  }

  Color get opacity60 {
    return withAlpha(153);
  }

  Color get opacity50 {
    return withAlpha(128);
  }

  Color get opacity38 {
    return withAlpha(97);
  }

  Color get opacity30 {
    return withAlpha(77);
  }

  Color get opacity12 {
    return withAlpha(31);
  }

  Color get opacity15 {
    return withAlpha(38);
  }

  Color get opacity10 {
    return withAlpha(15);
  }

  Color get opacity3 {
    return withAlpha(8); // ~3%
  }

  Color get opacity0 {
    return withAlpha(0);
  }

  int get value32bit {
    return _floatToInt8(a) << 24 |
        _floatToInt8(r) << 16 |
        _floatToInt8(g) << 8 |
        _floatToInt8(b) << 0;
  }

  int get alpha8bit => (0xff000000 & value32bit) >> 24;

  int get red8bit => (0x00ff0000 & value32bit) >> 16;

  int get green8bit => (0x0000ff00 & value32bit) >> 8;

  int get blue8bit => (0x000000ff & value32bit) >> 0;

  int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  Color lighten([double amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.white;
    final HSLColor hsl = this == const Color(0xFF000000)
        ? HSLColor.fromColor(this).withSaturation(0)
        : HSLColor.fromColor(this);
    return hsl
        .withLightness(min(1, max(0, hsl.lightness + amount / 100)))
        .toColor();
  }

  String get hex {
    final value = toARGB32();
    final red = (value >> 16) & 0xFF;
    final green = (value >> 8) & 0xFF;
    final blue = value & 0xFF;
    return '#${red.toRadixString(16).padLeft(2, '0')}'
            '${green.toRadixString(16).padLeft(2, '0')}'
            '${blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  Color darken([final int amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.black;
    final HSLColor hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness(min(1, max(0, hsl.lightness - amount / 100)))
        .toColor();
  }

  Color blendDarken(BuildContext context, {double factor = 0.1}) {
    final brightness = Theme.of(context).brightness;
    return Color.lerp(
      this,
      brightness == Brightness.dark ? Colors.white : Colors.black,
      factor,
    )!;
  }

  Color blendLighten(BuildContext context, {double factor = 0.1}) {
    final brightness = Theme.of(context).brightness;
    return Color.lerp(
      this,
      brightness == Brightness.dark ? Colors.black : Colors.white,
      factor,
    )!;
  }
}

/// Shared soft peach for compact CTAs (start / add profile) — not M3 primary.
abstract final class BrandSoft {
  static const Color fill = Color(0xFFFFE0A3);
  static const Color onFill = Color(0xFF4A3728);
}

extension ColorSchemeExtension on ColorScheme {
  ColorScheme toPureBlack(bool isPrueBlack) => isPrueBlack
      ? copyWith(
          surface: Colors.black,
          surfaceContainer: const Color(0xFF121212),
          surfaceContainerLow: const Color(0xFF0E0E0E),
          surfaceContainerHigh: const Color(0xFF1A1A1A),
          surfaceContainerHighest: const Color(0xFF222222),
          surfaceContainerLowest: Colors.black,
          surfaceTint: Colors.transparent,
        )
      : this;

  /// Whether [color] needs light (white) on-content for contrast.
  static bool _needsLightOn(Color color) {
    return color.computeLuminance() < 0.55;
  }

  /// Keep surfaces neutral and lock brand color.
  ///
  /// Material 3 [ColorScheme.fromSeed] often turns orange seeds into muddy
  /// brown/mustard for [primary]. Pass [brand] to force the real accent.
  ColorScheme toNeutralSurfaces({Color? brand}) {
    final brandColor = brand ?? primary;
    final onBrand = _needsLightOn(brandColor) ? Colors.white : Colors.black;
    final softSelect = Color.alphaBlend(
      brandColor.withValues(alpha: 0.12),
      brightness == Brightness.light ? Colors.white : surface,
    );

    // Soft mint — never muddy teal / olive.
    const mint = Color(0xFFA7F3D0);
    const mintSoft = Color(0xFFECFDF5);
    const mintOn = Color(0xFF166534);

    if (brightness != Brightness.light) {
      return copyWith(
        primary: brandColor,
        onPrimary: onBrand,
        primaryContainer: softSelect,
        onPrimaryContainer: brandColor,
        surfaceTint: Colors.transparent,
        secondary: mint,
        onSecondary: Colors.black,
        secondaryContainer: const Color(0xFF14532D),
        onSecondaryContainer: mint,
      );
    }

    const white = Color(0xFFFFFFFF);
    const paper = Color(0xFFFFFBF7);
    const line = Color(0xFFE8E4DF);
    const ink = Color(0xFF1C1917);
    const mute = Color(0xFF78716C);

    return copyWith(
      // Force soft brand orange — do not use M3-muddied primary.
      primary: brandColor,
      onPrimary: onBrand,
      primaryContainer: softSelect,
      onPrimaryContainer: ink,
      inversePrimary: brandColor,
      surface: white,
      surfaceDim: const Color(0xFFF5F5F4),
      surfaceBright: white,
      surfaceContainerLowest: white,
      surfaceContainerLow: paper,
      surfaceContainer: const Color(0xFFFAF8F5),
      surfaceContainerHigh: const Color(0xFFF5F2EC),
      surfaceContainerHighest: const Color(0xFFECE8E1),
      onSurface: ink,
      onSurfaceVariant: mute,
      outline: const Color(0xFFD6D3D1),
      outlineVariant: line,
      surfaceTint: Colors.transparent,
      secondary: mint,
      onSecondary: Colors.black,
      secondaryContainer: mintSoft,
      onSecondaryContainer: mintOn,
      tertiaryContainer: softSelect,
      onTertiaryContainer: ink,
    );
  }

  /// Upload chart: soft peach orange (never deep solid).
  Color get chartUp => const Color(0xFFFFD27A);

  /// Download chart: soft mint.
  Color get chartDown => const Color(0xFFA7F3D0);
}
