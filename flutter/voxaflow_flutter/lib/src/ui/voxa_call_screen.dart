import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../models/models.dart';
import '../sessions/call_session.dart';
import '../voxa_client.dart';
import 'voxa_call_controls.dart';
import 'voxa_call_theme.dart';
import 'voxa_reconnect_banner.dart';
import 'voxa_video_view.dart';

/// A full, drop-in in-call screen for a [CallSession] or [MeetingSession]
/// (anything that is an [RtcSession]).
///
/// It renders the participant video grid (focus + picture-in-picture for 1:1,
/// a grid for meetings, screen-share-priority when someone shares), a control bar
/// (mic / camera / screen-share / hold / end), a call timer and connection state.
/// Pass [client] to overlay the live transcript.
///
/// ```dart
/// final call = await client.startCall(video: true);
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => VoxaCallScreen(session: call, client: client, onEnded: () => Navigator.pop(context)),
/// ));
/// ```
class VoxaCallScreen extends StatefulWidget {
  const VoxaCallScreen({
    super.key,
    required this.session,
    this.client,
    this.title,
    this.theme = const VoxaCallTheme.midnight(),
    this.showScreenShare = true,
    this.showHold = true,
    this.showTranscript = false,
    this.onEnded,
    this.onMinimize,
  });

  final RtcSession session;

  /// Optional — enables the live transcript overlay ([showTranscript]).
  final VoxaClient? client;
  final String? title;
  final VoxaCallTheme theme;
  final bool showScreenShare;
  final bool showHold;

  /// Show a collapsible live-transcript panel. Requires [client].
  final bool showTranscript;

  /// Called after the session has ended (the screen does not pop itself).
  final VoidCallback? onEnded;

  /// If provided, a "minimize" affordance is shown (e.g. to drop to a
  /// [VoxaCallOverlay]); the screen does not pop itself.
  final VoidCallback? onMinimize;

  @override
  State<VoxaCallScreen> createState() => _VoxaCallScreenState();
}

class _VoxaCallScreenState extends State<VoxaCallScreen> {
  lk.Room get _room => widget.session.lkRoom;

  Timer? _timer;
  final _elapsed = Stopwatch();
  bool _micOn = true;
  bool _camOn = false;
  bool _screenSharing = false;
  bool _held = false;
  bool _ending = false;
  Offset _pipOffset = const Offset(16, 16);

  final List<TranscriptSegment> _finals = [];
  final Map<String, String> _interim = {};
  StreamSubscription<TranscriptSegment>? _transcriptSub;
  bool _transcriptOpen = false;

  @override
  void initState() {
    super.initState();
    _room.addListener(_onRoomChange);
    _syncLocalState();
    _elapsed.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.showTranscript && widget.client != null) {
      _transcriptSub = widget.client!.transcript.listen(_onTranscript);
    }
  }

  @override
  void dispose() {
    _room.removeListener(_onRoomChange);
    _transcriptSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _onRoomChange() {
    if (!mounted) return;
    _syncLocalState();
    setState(() {});
  }

  void _syncLocalState() {
    final me = _room.localParticipant;
    if (me != null) {
      _micOn = me.isMicrophoneEnabled();
      _camOn = me.isCameraEnabled();
      _screenSharing = me.isScreenShareEnabled();
    }
  }

  void _onTranscript(TranscriptSegment seg) {
    setState(() {
      if (seg.isFinal) {
        if (seg.id == null || _finals.every((f) => f.id != seg.id)) _finals.add(seg);
        _interim.remove(seg.speaker);
      } else {
        _interim[seg.speaker] = seg.text;
      }
    });
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    setState(() {});
    await widget.session.setMicEnabled(_micOn);
  }

  Future<void> _toggleCamera() async {
    _camOn = !_camOn;
    setState(() {});
    await widget.session.setCameraEnabled(_camOn);
  }

  Future<void> _toggleScreenShare() async {
    final next = !_screenSharing;
    _screenSharing = next;
    setState(() {});
    if (next) {
      await widget.session.startScreenShare();
    } else {
      await widget.session.stopScreenShare();
    }
  }

  Future<void> _toggleHold() async {
    _held = !_held;
    setState(() {});
    if (_held) {
      await widget.session.hold();
    } else {
      await widget.session.resume();
    }
  }

  Future<void> _end() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      await widget.session.end();
    } finally {
      widget.onEnded?.call();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(t),
            StreamBuilder<VoxaConnectionState>(
              stream: widget.session.connectionState,
              initialData: widget.session.state,
              builder: (_, snap) => VoxaReconnectBanner(
                state: snap.data ?? VoxaConnectionState.connected,
                onRejoin: widget.session.rejoinNow,
                theme: t,
              ),
            ),
            Expanded(child: _stage(t)),
            if (widget.showTranscript && widget.client != null) _transcriptPanel(t),
            VoxaCallControlBar(
              theme: t,
              micOn: _micOn,
              onToggleMic: _toggleMic,
              cameraOn: _camOn,
              onToggleCamera: _toggleCamera,
              screenSharing: widget.showScreenShare ? _screenSharing : null,
              onToggleScreenShare: widget.showScreenShare ? _toggleScreenShare : null,
              onHold: widget.showHold ? _toggleHold : null,
              held: _held,
              onEnd: _end,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(VoxaCallTheme t) {
    final connecting = _room.connectionState != lk.ConnectionState.connected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (widget.onMinimize != null)
            IconButton(
              onPressed: widget.onMinimize,
              icon: Icon(Icons.expand_more, color: t.onSurface),
              tooltip: 'Minimize',
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title ?? 'Voxa call',
                  style: TextStyle(color: t.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  connecting ? 'Connecting…' : _fmt(_elapsed.elapsed),
                  style: TextStyle(color: connecting ? t.accent : t.onSurfaceMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connecting ? t.accent : t.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage(VoxaCallTheme t) {
    final me = _room.localParticipant;
    final remotes = _room.remoteParticipants.values.toList();

    // Screen share takes the whole stage when present (local or remote).
    final sharer = [
      if (me != null) me,
      ...remotes,
    ].cast<lk.Participant?>().firstWhere(
          (p) => p != null && voxaScreenShareTrack(p) != null,
          orElse: () => null,
        );
    if (sharer != null) {
      return _screenShareStage(t, sharer, [if (me != null) me, ...remotes]);
    }

    // No one else yet → local fills, with a hint.
    if (remotes.isEmpty) {
      return Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: me != null
                ? VoxaParticipantTile(participant: me, theme: t, isLocal: true)
                : const SizedBox.shrink(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Text('Waiting for others to join…', style: TextStyle(color: t.onSurfaceMuted)),
            ),
          ),
        ],
      );
    }

    // 1:1 → remote focus + draggable local PiP.
    if (remotes.length == 1 && me != null) {
      return _focusWithPip(t, remotes.first, me);
    }

    // Meeting → grid of everyone.
    final all = <lk.Participant>[if (me != null) me, ...remotes];
    return _grid(t, all, localId: me?.identity);
  }

  Widget _focusWithPip(VoxaCallTheme t, lk.Participant remote, lk.LocalParticipant me) {
    return LayoutBuilder(
      builder: (context, c) {
        const pipW = 110.0;
        const pipH = 150.0;
        final maxX = c.maxWidth - pipW - 12;
        final maxY = c.maxHeight - pipH - 12;
        final dx = _pipOffset.dx.clamp(12.0, maxX < 12 ? 12.0 : maxX);
        final dy = _pipOffset.dy.clamp(12.0, maxY < 12 ? 12.0 : maxY);
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: VoxaParticipantTile(participant: remote, theme: t),
            ),
            Positioned(
              left: dx,
              top: dy,
              width: pipW,
              height: pipH,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _pipOffset = Offset(dx + d.delta.dx, dy + d.delta.dy)),
                child: VoxaParticipantTile(participant: me, theme: t, isLocal: true, borderRadius: 12),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _screenShareStage(VoxaCallTheme t, lk.Participant sharer, List<lk.Participant> all) {
    final share = voxaScreenShareTrack(sharer)!;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: t.surfaceVariant,
                child: lk.VideoTrackRenderer(share, fit: lk.VideoViewFit.contain),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => AspectRatio(
              aspectRatio: 3 / 4,
              child: VoxaParticipantTile(
                participant: all[i],
                theme: t,
                isLocal: all[i].identity == _room.localParticipant?.identity,
                borderRadius: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _grid(VoxaCallTheme t, List<lk.Participant> all, {String? localId}) {
    final cols = all.length <= 2 ? 1 : 2;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3 / 4,
        ),
        itemCount: all.length,
        itemBuilder: (_, i) => VoxaParticipantTile(
          participant: all[i],
          theme: t,
          isLocal: all[i].identity == localId,
        ),
      ),
    );
  }

  Widget _transcriptPanel(VoxaCallTheme t) {
    final lines = [
      ..._finals.map((s) => '${s.speaker}: ${s.text}'),
      ..._interim.entries.map((e) => '${e.key}: ${e.value}'),
    ];
    return Material(
      color: t.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.subtitles, color: t.onSurfaceMuted),
            title: Text('Live transcript', style: TextStyle(color: t.onSurface, fontSize: 13)),
            trailing: Icon(_transcriptOpen ? Icons.expand_more : Icons.expand_less, color: t.onSurfaceMuted),
            onTap: () => setState(() => _transcriptOpen = !_transcriptOpen),
          ),
          if (_transcriptOpen)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Listening…', style: TextStyle(color: t.onSurfaceMuted)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        for (final l in lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(l, style: TextStyle(color: t.onSurface, fontSize: 13)),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
