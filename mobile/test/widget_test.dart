import 'package:flutter_test/flutter_test.dart';

import 'package:syncronization/app.dart';

void main() {
  testWidgets('Syncronization app renders home screen', (tester) async {
    await tester.pumpWidget(const SyncronizationApp(enableDiscovery: false));
    await tester.pump();

    expect(find.text('Syncronization'), findsOneWidget);
  });
}
