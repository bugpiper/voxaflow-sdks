import 'package:flutter/material.dart';

/// Design tokens for the prebuilt Voxa call UI (in-call / incoming / overlay).
///
/// Defaults to the "Midnight Intelligence" dark palette used across Voxa. Pass a
/// custom [VoxaCallTheme] to any prebuilt widget to re-skin it, or use
/// [VoxaCallTheme.light] for a light surface.
@immutable
class VoxaCallTheme {
  const VoxaCallTheme({
    this.background = const Color(0xFF0A0E1A),
    this.surface = const Color(0xFF141A2E),
    this.surfaceVariant = const Color(0xFF1E2740),
    this.primary = const Color(0xFF6366F1),
    this.onPrimary = Colors.white,
    this.accent = const Color(0xFF818CF8),
    this.danger = const Color(0xFFEF4444),
    this.success = const Color(0xFF22C55E),
    this.onSurface = const Color(0xFFE6E9F2),
    this.onSurfaceMuted = const Color(0xFF8A93AD),
    this.controlBackground = const Color(0xFF232C45),
    this.brightnessIsDark = true,
  });

  /// The Midnight Intelligence dark theme (default).
  const VoxaCallTheme.midnight() : this();

  /// A light variant for apps that don't run a dark call UI.
  const VoxaCallTheme.light()
      : this(
          background: const Color(0xFFF4F5FB),
          surface: Colors.white,
          surfaceVariant: const Color(0xFFEAECF5),
          primary: const Color(0xFF4F46E5),
          onPrimary: Colors.white,
          accent: const Color(0xFF6366F1),
          danger: const Color(0xFFDC2626),
          success: const Color(0xFF16A34A),
          onSurface: const Color(0xFF131726),
          onSurfaceMuted: const Color(0xFF6B7280),
          controlBackground: const Color(0xFFE2E5F0),
          brightnessIsDark: false,
        );

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color danger;
  final Color success;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color controlBackground;
  final bool brightnessIsDark;
}
