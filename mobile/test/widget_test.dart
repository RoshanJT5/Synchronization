import 'package:flutter_test/flutter_test.dart';

import 'package:synchronization/app.dart';

void main() {
  testWidgets('Synchronization app renders home screen', (tester) async {
    await tester.pumpWidget(const SynchronizationApp(enableDiscovery: false));
    await tester.pump();

    expect(find.text('Synchronization'), findsOneWidget);
  });
}
