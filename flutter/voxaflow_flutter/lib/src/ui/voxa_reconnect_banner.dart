import 'package:flutter/material.dart';

import '../models/models.dart';
import 'voxa_call_theme.dart';

/// Meet-style "connection lost" strip: shown while the SDK auto-rejoins (with "Rejoin now"),
/// and with "Rejoin" once it gives up. Renders nothing while connected/connecting.
/// Drive it from `session.connectionState` and pass `session.rejoinNow`.
class VoxaReconnectBanner extends StatelessWidget {
  const VoxaReconnectBanner({super.key, required this.state, required this.onRejoin, this.attempt = 0, this.theme = const VoxaCallTheme()});

  final VoxaConnectionState state;
  final VoidCallback onRejoin;

  /// Current auto-rejoin attempt (`session.rejoinAttemptNumber`); 0 hides "(attempt n)".
  final int attempt;
  final VoxaCallTheme theme;

  @override
  Widget build(BuildContext context) {
    final reconnecting = state == VoxaConnectionState.reconnecting;
    if (!reconnecting && state != VoxaConnectionState.disconnected) return const SizedBox.shrink();
    final bg = reconnecting ? theme.accent : theme.danger;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: bg.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(reconnecting ? Icons.wifi_off : Icons.link_off, size: 16, color: bg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reconnecting
                    ? 'Connection lost — reconnecting…${attempt > 0 ? ' (attempt $attempt)' : ''}'
                    : 'Connection lost. Check your network, then rejoin.',
                style: TextStyle(color: theme.onSurface, fontSize: 13),
              ),
            ),
            TextButton(onPressed: onRejoin, child: Text(reconnecting ? 'Rejoin now' : 'Rejoin')),
          ],
        ),
      ),
    );
  }
}
