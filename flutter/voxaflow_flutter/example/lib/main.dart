import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voxaflow_flutter/voxaflow_flutter.dart';

void main() => runApp(const VoxaExampleApp());

class VoxaExampleApp extends StatelessWidget {
  const VoxaExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voxa Flow SDK Example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _endpoint = TextEditingController(text: 'https://voxaflow.fastwheel.ai/api');
  final _token = TextEditingController();
  String? _error;
  bool _connecting = false;

  Future<void> _connect() async {
    setState(() {
      _error = null;
      _connecting = true;
    });
    final client = VoxaClient(VoxaConfig(endpoint: _endpoint.text.trim(), token: _token.text.trim()));
    try {
      await client.connect();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(client: client)));
    } on VoxaError catch (e) {
      setState(() => _error = e.message);
      await client.disconnect();
    } catch (e) {
      setState(() => _error = '$e');
      await client.disconnect();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voxa Flow SDK')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Paste a Voxa access token (a logged-in JWT) to connect.'),
            const SizedBox(height: 16),
            TextField(controller: _endpoint, decoration: const InputDecoration(labelText: 'API endpoint')),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              decoration: const InputDecoration(labelText: 'Access token (JWT)'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _connecting ? null : _connect,
              child: _connecting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Connect'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.client});
  final VoxaClient client;
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallSession? _call;
  VoxaConnectionState _conn = VoxaConnectionState.connected;
  bool _micOn = true;
  bool _busy = false;
  final List<TranscriptSegment> _finals = [];
  final Map<String, String> _interim = {};
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(widget.client.connectionState.listen((s) => setState(() => _conn = s)));
    _subs.add(widget.client.transcript.listen((seg) => setState(() {
          if (seg.isFinal) {
            if (seg.id == null || _finals.every((f) => f.id != seg.id)) _finals.add(seg);
            _interim.remove(seg.speaker);
          } else {
            _interim[seg.speaker] = seg.text;
          }
        })));
  }

  Future<void> _startCall({required bool video}) async {
    setState(() => _busy = true);
    try {
      await Permission.microphone.request();
      if (video) await Permission.camera.request();
      _call = await widget.client.startCall(video: video);
    } on VoxaError catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMic() async {
    final c = _call;
    if (c == null) return;
    _micOn = !_micOn;
    await c.setMicEnabled(_micOn);
    setState(() {});
  }

  Future<void> _end() async {
    await _call?.end();
    _call = null;
    setState(() {});
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _call?.end();
    widget.client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.client.profile;
    final inCall = _call != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live transcript'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('${p.role} · ${_conn.name}')),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (!inCall) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _startCall(video: false),
                    icon: const Icon(Icons.call),
                    label: const Text('Start call'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _startCall(video: true),
                    icon: const Icon(Icons.videocam),
                    label: const Text('Video'),
                  ),
                ] else ...[
                  IconButton.filledTonal(
                    onPressed: _toggleMic,
                    icon: Icon(_micOn ? Icons.mic : Icons.mic_off),
                    tooltip: _micOn ? 'Mute' : 'Unmute',
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _end,
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    icon: const Icon(Icons.call_end),
                    label: const Text('End'),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: (_finals.isEmpty && _interim.isEmpty)
                ? const Center(child: Text('Speak after starting the call — your words appear here.'))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final s in _finals)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: '${s.speaker}:  ', style: const TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: s.text),
                          ])),
                        ),
                      for (final e in _interim.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Opacity(
                            opacity: 0.55,
                            child: Text('${e.key}:  ${e.value}', style: const TextStyle(fontStyle: FontStyle.italic)),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
