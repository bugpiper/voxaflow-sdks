// Runtime smoke test against a live Voxa backend. Proves the SDK DATA PATH end-to-end:
// realtime connect (Socket.IO auth) + a REST call + role/capability parsing. Does NOT
// exercise LiveKit media (that needs a device/emulator).
//
// Run:  flutter test test/runtime_prod_test.dart \
//         --dart-define=VOXA_ENDPOINT=https://voxaflow.fastwheel.ai/api \
//         --dart-define=VOXA_TOKEN=<a valid Voxa JWT>
//
// Without VOXA_TOKEN it is skipped, so a plain `flutter test` stays green.

import 'package:flutter_test/flutter_test.dart';
import 'package:voxaflow_flutter/voxaflow_flutter.dart';

void main() {
  const endpoint = String.fromEnvironment('VOXA_ENDPOINT', defaultValue: 'https://voxaflow.fastwheel.ai/api');
  const token = String.fromEnvironment('VOXA_TOKEN');

  test('connects to prod, parses the token, and runs a REST call', () async {
    final client = VoxaClient(VoxaConfig(endpoint: endpoint, token: token));
    final states = <VoxaConnectionState>[];
    final sub = client.connectionState.listen(states.add);

    await client.connect();
    expect(client.profile.role, isNotEmpty);

    // A capability-gated REST call (agent tokens only). Just proves auth + REST + parse.
    if (client.can(Capability.callControl)) {
      final calls = await client.getActiveCalls();
      // ignore: avoid_print
      print('role=${client.profile.role} activeCalls=${calls.length} states=$states');
    }

    await sub.cancel();
    await client.disconnect();
  }, skip: token.isEmpty ? 'set --dart-define=VOXA_TOKEN to run' : false, timeout: const Timeout(Duration(seconds: 30)));
}
