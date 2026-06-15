import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoViewObjectFit;

import '../sessions/call_session.dart';
import 'voxa_call_theme.dart';
import 'voxa_video_view.dart';

/// A draggable floating mini call window (picture-in-picture) for an ongoing
/// [RtcSession]. Place it as the top layer of a [Stack] (empty areas let touches
/// through), or use [VoxaCallOverlayController] to float it over the whole app.
///
/// Shows the remote video (or an avatar) plus a running timer; tap to expand.
class VoxaCallOverlay extends StatefulWidget {
  const VoxaCallOverlay({
    super.key,
    required this.session,
    this.theme = const VoxaCallTheme.midnight(),
    this.onTap,
    this.onEnd,
    this.initialOffset = const Offset(16, 80),
    this.size = const Size(120, 168),
  });

  final RtcSession session;
  final VoxaCallTheme theme;

  /// Tapped the pill (typically: restore the full [VoxaCallScreen]).
  final VoidCallback? onTap;

  /// Optional end-call button on the pill.
  final VoidCallback? onEnd;
  final Offset initialOffset;
  final Size size;

  @override
  State<VoxaCallOverlay> createState() => _VoxaCallOverlayState();
}

class _VoxaCallOverlayState extends State<VoxaCallOverlay> {
  lk.Room get _room => widget.session.lkRoom;
  late Offset _offset = widget.initialOffset;
  Timer? _timer;
  final _elapsed = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _room.addListener(_onChange);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _room.removeListener(_onChange);
    _timer?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final remote = _room.remoteParticipants.values.cast<lk.Participant?>().firstWhere(
          (p) => p != null && voxaCameraTrack(p) != null,
          orElse: () => _room.remoteParticipants.values.isNotEmpty ? _room.remoteParticipants.values.first : null,
        );
    final video = remote == null ? null : voxaCameraTrack(remote);

    return LayoutBuilder(
      builder: (context, c) {
        final maxX = (c.maxWidth - widget.size.width - 8).clamp(8.0, double.infinity);
        final maxY = (c.maxHeight - widget.size.height - 8).clamp(8.0, double.infinity);
        final dx = _offset.dx.clamp(8.0, maxX);
        final dy = _offset.dy.clamp(8.0, maxY);
        return Stack(
          children: [
            Positioned(
              left: dx,
              top: dy,
              width: widget.size.width,
              height: widget.size.height,
              child: GestureDetector(
                onTap: widget.onTap,
                onPanUpdate: (d) => setState(() => _offset = Offset(dx + d.delta.dx, dy + d.delta.dy)),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  color: t.surfaceVariant,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (video != null)
                        lk.VideoTrackRenderer(video, fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                      else
                        Center(child: Icon(Icons.phone_in_talk, color: t.onSurfaceMuted, size: 28)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            _fmt(_elapsed.elapsed),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      if (widget.onEnd != null)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Material(
                            color: t.danger,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: widget.onEnd,
                              child: const SizedBox(
                                width: 24,
                                height: 24,
                                child: Icon(Icons.call_end, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Floats a [VoxaCallOverlay] over the entire app via the root [Overlay].
///
/// ```dart
/// final overlay = VoxaCallOverlayController();
/// overlay.show(context, session: call, onTap: () { overlay.hide(); /* reopen screen */ });
/// // later: overlay.hide();
/// ```
class VoxaCallOverlayController {
  OverlayEntry? _entry;

  bool get isShowing => _entry != null;

  void show(
    BuildContext context, {
    required RtcSession session,
    VoxaCallTheme theme = const VoxaCallTheme.midnight(),
    VoidCallback? onTap,
    VoidCallback? onEnd,
  }) {
    hide();
    final entry = OverlayEntry(
      builder: (_) => VoxaCallOverlay(
        session: session,
        theme: theme,
        onTap: onTap,
        onEnd: onEnd,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    _entry = entry;
  }

  void hide() {
    _entry?.remove();
    _entry = null;
  }
}
