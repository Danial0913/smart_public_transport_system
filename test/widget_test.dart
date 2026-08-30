import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_tublic_transport_system/main.dart';

void main() {
  testWidgets('App shows the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartTransportApp());

    expect(find.text('Smart Public Transport'), findsOneWidget);
    expect(find.text('Plan smarter. Travel better.'), findsOneWidget);

    // Dispose the splash screen so its Timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
