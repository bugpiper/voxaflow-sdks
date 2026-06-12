import 'package:flutter/material.dart';

import '../native/voxa_callkit.dart';
import 'voxa_call_theme.dart';

/// A full-screen, in-app **incoming call** (ringing) UI.
///
/// Use this when the app is already foregrounded and you want a branded ring
/// screen. For background / killed-app ringing, use [VoxaCallKit] (native
/// CallKit / full-screen notification) instead — this widget complements it.
///
/// ```dart
/// showDialog(context: context, barrierDismissible: false, builder: (_) =>
///   VoxaIncomingCallScreen(
///     call: VoxaIncomingCall(callId: id, callerName: 'Astrologer Maya', video: true),
///     onAccept: ({required video}) async { Navigator.pop(context); /* startCall */ },
///     onDecline: () => Navigator.pop(context),
///   ));
/// ```
class VoxaIncomingCallScreen extends StatefulWidget {
  const VoxaIncomingCallScreen({
    super.key,
    required this.call,
    required this.onAccept,
    required this.onDecline,
    this.theme = const VoxaCallTheme.midnight(),
    this.subtitle,
  });

  final VoxaIncomingCall call;

  /// Tapped "Accept". [video] reflects which accept button was used (the plain
  /// accept button uses the call's own [VoxaIncomingCall.video]).
  final void Function({required bool video}) onAccept;
  final VoidCallback onDecline;
  final VoxaCallTheme theme;

  /// Overrides the default "Incoming voice/video call" line.
  final String? subtitle;

  @override
  State<VoxaIncomingCallScreen> createState() => _VoxaIncomingCallScreenState();
}

class _VoxaIncomingCallScreenState extends State<VoxaIncomingCallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final c = widget.call;
    final subtitle = widget.subtitle ?? 'Incoming ${c.video ? 'video' : 'voice'} call';
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const Spacer(),
              _pulsingAvatar(t, c),
              const SizedBox(height: 28),
              Text(
                c.callerName.isEmpty ? 'Unknown' : c.callerName,
                style: TextStyle(color: t.onSurface, fontSize: 26, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: TextStyle(color: t.onSurfaceMuted, fontSize: 15)),
              const Spacer(flex: 2),
              _actions(t, c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pulsingAvatar(VoxaCallTheme t, VoxaIncomingCall c) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final v = _pulse.value;
        return SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final phase in [0.0, 0.5])
                Opacity(
                  opacity: (1 - ((v + phase) % 1.0)).clamp(0.0, 1.0) * 0.4,
                  child: Container(
                    width: 120 + ((v + phase) % 1.0) * 60,
                    height: 120 + ((v + phase) % 1.0) * 60,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: t.primary),
                  ),
                ),
              child!,
            ],
          ),
        );
      },
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [t.primary, t.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: c.avatar != null && c.avatar!.isNotEmpty
            ? ClipOval(child: Image.network(c.avatar!, width: 110, height: 110, fit: BoxFit.cover))
            : Icon(c.video ? Icons.videocam : Icons.person, color: t.onPrimary, size: 48),
      ),
    );
  }

  Widget _actions(VoxaCallTheme t, VoxaIncomingCall c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _bigButton(
          color: t.danger,
          icon: Icons.call_end,
          label: 'Decline',
          onTap: widget.onDecline,
        ),
        if (c.video)
          _bigButton(
            color: t.surfaceVariant,
            icon: Icons.videocam,
            label: 'Video',
            onTap: () => widget.onAccept(video: true),
          ),
        _bigButton(
          color: t.success,
          icon: c.video ? Icons.call : Icons.call,
          label: 'Accept',
          onTap: () => widget.onAccept(video: c.video),
        ),
      ],
    );
  }

  Widget _bigButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 68, height: 68, child: Icon(icon, color: Colors.white, size: 30)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: widget.theme.onSurfaceMuted, fontSize: 13)),
      ],
    );
  }
}
