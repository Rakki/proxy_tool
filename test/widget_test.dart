import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:proxy_tool/main.dart';

void main() {
  testWidgets('shows empty connections state', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const ProxyToolApp());
    await tester.pumpAndSettle();

    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('No connections yet'), findsOneWidget);
    expect(find.text('Add connection'), findsOneWidget);
  });
}
