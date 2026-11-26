import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wired_test/pages/menu/menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    FlutterSecureStorage.setMockInitialValues({'authToken': 'test-token'});
    PackageInfo.setMockInitialValues(
      appName: 'HealthMAP',
      packageName: 'test.healthmap',
      version: '9.8.7',
      buildNumber: '654',
      buildSignature: '',
    );
  });
  tearDown(dotenv.clean);

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('version scrolls safely below menu: $brightness, $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"id":1,"first_name":"Test","createdAt":"2025-01-01","quizScores":[]}',
            200,
          );
        });
        addTearDown(client.close);
        await http.runWithClient(() async {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.symmetric(vertical: 24),
                // The test font is wider than the app font in account labels.
                textScaler: const TextScaler.linear(0.7),
              ),
              child: child!,
            ),
            home: const Menu(),
          ));
          await tester.pumpAndSettle();
          final footer = find.text('Version 9.8.7 (654)');
          expect(footer, findsOneWidget);
          expect(find.text('About WiRED'), findsOneWidget);
          expect(find.text('Classes'), findsOneWidget);
          expect(find.text('Delete Account'), findsOneWidget);
          expect(
              find.ancestor(
                  of: footer, matching: find.byType(SingleChildScrollView)),
              findsOneWidget);
          await tester.ensureVisible(footer);
          await tester.pumpAndSettle();
          expect(
              tester.getTopLeft(footer).dy,
              greaterThan(
                  tester.getBottomRight(find.text('Delete Account')).dy));
          final rect = tester.getRect(footer);
          expect(rect.top, greaterThanOrEqualTo(24));
          expect(rect.bottom, lessThanOrEqualTo(size.height - 24));
          final scrollRect = tester.getRect(find.ancestor(
              of: footer, matching: find.byType(SingleChildScrollView)));
          expect(rect.center.dx, closeTo(scrollRect.center.dx, 1));
          final text = tester.widget<Text>(footer);
          expect(text.textAlign, TextAlign.center);
          expect(text.style!.fontSize, 12);
          expect(text.style!.color, Colors.black54);

          // The version uses local metadata, with no additional HTTP request.
          expect(requests.map((r) => r.url.path), ['/users/me']);
        }, () => client);
      });
    }
  }

  testWidgets('installed version remains available with no offline profile',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: Menu()));
    await tester.pumpAndSettle();
    expect(find.textContaining('User is not logged in'), findsOneWidget);
    expect(find.text('Version 9.8.7 (654)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('version does not wait for a profile network response',
      (tester) async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    addTearDown(client.close);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Menu()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Version 9.8.7 (654)'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      response.complete(http.Response('{}', 503));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('incomplete metadata hides the footer without a placeholder',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'HealthMAP',
      packageName: 'test.healthmap',
      version: '',
      buildNumber: '654',
      buildSignature: '',
    );
    await tester.pumpWidget(const MaterialApp(home: Menu()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version '), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
