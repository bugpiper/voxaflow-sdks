import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxaflow_flutter/voxaflow_flutter.dart';

Widget host(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('hidden while connected', (t) async {
    await t.pumpWidget(host(VoxaReconnectBanner(state: VoxaConnectionState.connected, onRejoin: () {})));
    expect(find.textContaining('reconnecting'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('reconnecting: banner + "Rejoin now" calls onRejoin', (t) async {
    var taps = 0;
    await t.pumpWidget(host(VoxaReconnectBanner(state: VoxaConnectionState.reconnecting, onRejoin: () => taps++)));
    expect(find.text('Connection lost — reconnecting…'), findsOneWidget);
    await t.tap(find.text('Rejoin now'));
    expect(taps, 1);
  });

  testWidgets('disconnected (gave up): "Disconnected" + "Rejoin"', (t) async {
    var taps = 0;
    await t.pumpWidget(host(VoxaReconnectBanner(state: VoxaConnectionState.disconnected, onRejoin: () => taps++)));
    expect(find.text('Disconnected'), findsOneWidget);
    await t.tap(find.text('Rejoin'));
    expect(taps, 1);
  });
}
