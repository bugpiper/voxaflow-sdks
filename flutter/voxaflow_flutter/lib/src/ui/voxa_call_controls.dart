import 'package:flutter/material.dart';

import 'voxa_call_theme.dart';

/// A single round call-control button (mic, camera, end, …).
class VoxaControlButton extends StatelessWidget {
  const VoxaControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.theme = const VoxaCallTheme.midnight(),
    this.active = true,
    this.danger = false,
    this.label,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoxaCallTheme theme;

  /// When false the button reads as "off/disabled-state" (e.g. mic muted) and is
  /// rendered in a muted style.
  final bool active;
  final bool danger;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final Color bg = danger
        ? t.danger
        : active
            ? t.controlBackground
            : t.onSurface.withValues(alpha: 0.9);
    final Color fg = danger || !active ? Colors.white : t.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: danger || !active ? (danger ? Colors.white : t.background) : fg, size: size * 0.42),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(label!, style: TextStyle(color: t.onSurfaceMuted, fontSize: 11)),
        ],
      ],
    );
  }
}

/// The standard in-call control row: mic, camera, screen-share, hold, end.
/// Any callback left null hides that control.
class VoxaCallControlBar extends StatelessWidget {
  const VoxaCallControlBar({
    super.key,
    this.theme = const VoxaCallTheme.midnight(),
    required this.micOn,
    required this.onToggleMic,
    this.cameraOn,
    this.onToggleCamera,
    this.screenSharing,
    this.onToggleScreenShare,
    this.onHold,
    this.held = false,
    required this.onEnd,
  });

  final VoxaCallTheme theme;
  final bool micOn;
  final VoidCallback onToggleMic;

  /// Null hides the camera button (audio-only call).
  final bool? cameraOn;
  final VoidCallback? onToggleCamera;

  /// Null hides the screen-share button (e.g. not supported on this platform).
  final bool? screenSharing;
  final VoidCallback? onToggleScreenShare;

  final VoidCallback? onHold;
  final bool held;

  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            VoxaControlButton(
              theme: t,
              icon: micOn ? Icons.mic : Icons.mic_off,
              active: micOn,
              onPressed: onToggleMic,
              label: micOn ? 'Mute' : 'Unmute',
            ),
            if (cameraOn != null && onToggleCamera != null)
              VoxaControlButton(
                theme: t,
                icon: cameraOn! ? Icons.videocam : Icons.videocam_off,
                active: cameraOn!,
                onPressed: onToggleCamera,
                label: 'Camera',
              ),
            if (screenSharing != null && onToggleScreenShare != null)
              VoxaControlButton(
                theme: t,
                icon: screenSharing! ? Icons.stop_screen_share : Icons.screen_share,
                active: !screenSharing!,
                onPressed: onToggleScreenShare,
                label: 'Share',
              ),
            if (onHold != null)
              VoxaControlButton(
                theme: t,
                icon: held ? Icons.play_arrow : Icons.pause,
                active: !held,
                onPressed: onHold,
                label: held ? 'Resume' : 'Hold',
              ),
            VoxaControlButton(
              theme: t,
              icon: Icons.call_end,
              danger: true,
              onPressed: onEnd,
              label: 'End',
            ),
          ],
        ),
      ),
    );
  }
}
