import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoViewObjectFit;

import 'voxa_call_theme.dart';

/// The participant's live **camera** video track (ignores screen share), or null
/// if they have no subscribed/unmuted camera track.
lk.VideoTrack? voxaCameraTrack(lk.Participant p) {
  for (final pub in p.videoTrackPublications) {
    if (pub.source == lk.TrackSource.screenShareVideo) continue;
    final t = pub.track;
    if (t is lk.VideoTrack && !pub.muted) return t;
  }
  return null;
}

/// The participant's live **screen-share** video track, or null.
lk.VideoTrack? voxaScreenShareTrack(lk.Participant p) {
  for (final pub in p.videoTrackPublications) {
    if (pub.source != lk.TrackSource.screenShareVideo) continue;
    final t = pub.track;
    if (t is lk.VideoTrack && !pub.muted) return t;
  }
  return null;
}

/// A human label for a participant — name, else a cleaned-up identity.
String voxaParticipantLabel(lk.Participant p, {String? localSuffix}) {
  var label = p.name.trim();
  if (label.isEmpty) {
    final id = p.identity;
    // Friendlier than raw "guest_ab12cd" identities.
    label = id.startsWith('guest_') ? 'Guest' : id;
  }
  return localSuffix != null ? '$label $localSuffix' : label;
}

/// Renders one participant: their camera (or an avatar placeholder), with a name
/// chip, mic-muted indicator and an active-speaker ring. Rebuilds itself on the
/// participant's own change notifications (track add/remove, mute, speaking).
class VoxaParticipantTile extends StatefulWidget {
  const VoxaParticipantTile({
    super.key,
    required this.participant,
    this.theme = const VoxaCallTheme.midnight(),
    this.isLocal = false,
    this.mirror,
    this.fit = RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    this.showLabel = true,
    this.borderRadius = 16,
  });

  final lk.Participant participant;
  final VoxaCallTheme theme;
  final bool isLocal;

  /// Mirror the video horizontally. Defaults to true for the local camera.
  final bool? mirror;
  final RTCVideoViewObjectFit fit;
  final bool showLabel;
  final double borderRadius;

  @override
  State<VoxaParticipantTile> createState() => _VoxaParticipantTileState();
}

class _VoxaParticipantTileState extends State<VoxaParticipantTile> {
  @override
  void initState() {
    super.initState();
    widget.participant.addListener(_onChange);
  }

  @override
  void didUpdateWidget(VoxaParticipantTile old) {
    super.didUpdateWidget(old);
    if (old.participant != widget.participant) {
      old.participant.removeListener(_onChange);
      widget.participant.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final p = widget.participant;
    final cam = voxaCameraTrack(p);
    final speaking = p.isSpeaking;
    final muted = p.isMuted;
    final mirror = widget.mirror ?? widget.isLocal;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        decoration: BoxDecoration(
          color: t.surfaceVariant,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: speaking ? t.accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cam != null)
              lk.VideoTrackRenderer(
                cam,
                fit: widget.fit,
                mirrorMode: mirror ? lk.VideoViewMirrorMode.mirror : lk.VideoViewMirrorMode.off,
              )
            else
              _Avatar(theme: t, label: voxaParticipantLabel(p)),
            if (widget.showLabel)
              Positioned(
                left: 8,
                bottom: 8,
                child: _NameChip(
                  theme: t,
                  label: voxaParticipantLabel(p, localSuffix: widget.isLocal ? '(You)' : null),
                  muted: muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.theme, required this.label});
  final VoxaCallTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(label);
    return Container(
      color: theme.surfaceVariant,
      alignment: Alignment.center,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [theme.primary, theme.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: TextStyle(color: theme.onPrimary, fontSize: 26, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static String _initials(String label) {
    final parts = label.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts.first.characters.take(1).toString() + parts[1].characters.take(1).toString()).toUpperCase();
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.theme, required this.label, required this.muted});
  final VoxaCallTheme theme;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (muted) ...[
            Icon(Icons.mic_off, size: 14, color: theme.danger),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
