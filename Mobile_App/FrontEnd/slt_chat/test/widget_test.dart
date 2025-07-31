import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slt_chat/SplashScreen.dart';

import 'package:slt_chat/main.dart';

void main() {
  testWidgets('App shows login or splash without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(
      find.byType(SplashScreen),
      findsOneWidget,
    ); // likely showing SplashScreen at start
  });
}
