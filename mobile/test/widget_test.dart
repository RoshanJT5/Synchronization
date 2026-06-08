import 'package:flutter_test/flutter_test.dart';

import 'package:synchronization/app.dart';

void main() {
  testWidgets('Synchronization app renders home screen', (tester) async {
    await tester.pumpWidget(const SynchronizationApp(enableDiscovery: false));
    await tester.pump();
    // The app now gates the main UI behind a Location Permission screen,
    // so the initial text we expect to see is 'Location Required'.
    expect(find.text('Location Required'), findsOneWidget);
  });
}
