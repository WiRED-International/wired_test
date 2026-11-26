import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/pages/menu/menu.dart';

// A separate test isolate keeps PackageInfo's successful-result cache empty.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    dotenv.clean();
  });

  testWidgets('platform metadata failure is silent and leaves menu usable',
      (tester) async {
    var lookups = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAll');
      lookups++;
      throw PlatformException(code: 'metadata-unavailable');
    });
    await tester.pumpWidget(const MaterialApp(home: Menu()));
    await tester.pumpAndSettle();
    expect(lookups, 1);
    expect(find.textContaining('Version '), findsNothing);
    expect(find.textContaining('metadata-unavailable'), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending metadata stays hidden and may fail after disposal safely',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (_) => response.future);
    await tester.pumpWidget(const MaterialApp(home: Menu()));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version '), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    response.completeError(PlatformException(code: 'late-failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
