import 'package:flutter_test/flutter_test.dart';
import 'package:voxaflow_example/main.dart';

void main() {
  testWidgets('renders the connect screen', (tester) async {
    await tester.pumpWidget(const VoxaExampleApp());
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Voxa Flow SDK'), findsOneWidget);
  });
}
