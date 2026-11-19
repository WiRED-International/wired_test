import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wired_test/main.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:wired_test/utils/updateChecker.dart';

void main() {
  testWidgets('installed version lookup failure safely returns no version',
      (tester) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      throw PlatformException(code: 'lookup-failed');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(await UpdateChecker.getInstalledVersion(), isNull);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stalled installed version lookup times out without late errors',
      (tester) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final response = Completer<Map<String, dynamic>>();
    var started = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      started = true;
      return response.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var completed = false;
    final pending = UpdateChecker.getInstalledVersion().then((value) {
      completed = true;
      return value;
    });
    await tester.pump();
    expect(started, isTrue);
    expect(completed, isFalse);
    await tester.pump(const Duration(seconds: 15));
    expect(completed, isTrue);
    expect(await pending, isNull);
    response.completeError(PlatformException(code: 'late-lookup-failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final version in ['', 'not-a-version', '1.2.3.4']) {
    testWidgets(
        'missing or malformed installed version safely skips check: $version',
        (tester) async {
      PackageInfo.setMockInitialValues(
          appName: 'HealthMAP',
          packageName: 'com.example.healthmap.test',
          version: version,
          buildNumber: '1',
          buildSignature: '');
      late BuildContext caller;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        caller = context;
        return const Scaffold(body: Text('Version caller'));
      })));
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      await http.runWithClient(
          () => UpdateChecker.checkForUpdate(caller), () => client);
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final disposed in [false, true]) {
    testWidgets(
        'delayed update dialog ${disposed ? 'ignores disposed context' : 'shows while mounted'}',
        (tester) async {
      late BuildContext caller;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        caller = context;
        return const Scaffold(body: Text('Update caller'));
      })));
      final response = Completer<void>();
      final pending = response.future.then((_) {
        UpdateChecker.showUpdateDialog(caller);
      });
      if (disposed) {
        await tester.pumpWidget(const SizedBox.shrink());
        expect(caller.mounted, isFalse);
      }
      response.complete();
      await tester.pump();
      await pending;
      await tester.pumpAndSettle();
      expect(find.text('Update Available'),
          disposed ? findsNothing : findsOneWidget);
      if (!disposed) {
        expect(
            find.text(
                'A new version of the app is available. Please update for the best experience.'),
            findsOneWidget);
        expect(find.text('Update Now'), findsOneWidget);
        await tester.tap(find.text('Later'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
        'HealthMAP home renders and loads a mocked alert at width $width',
        (tester) async {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      addTearDown(dotenv.clean);
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      PackageInfo.setMockInitialValues(
        appName: 'HealthMAP',
        packageName: 'com.example.healthmap.test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const alertText = 'HealthMAP smoke test update';
      final requests = <Uri>[];
      final unexpectedRequests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.method != 'GET' ||
            request.url != Uri.parse('https://example.invalid/alerts/latest')) {
          unexpectedRequests.add(request.url);
          throw StateError(
              'Unexpected HTTP request: ${request.method} ${request.url}');
        }
        return http.Response(
            jsonEncode({'alert': alertText, 'important': false}), 200,
            headers: {'content-type': 'application/json'});
      });
      addTearDown(client.close);

      await http.runWithClient(() async {
        try {
          await tester.pumpWidget(const MyApp());
          await tester.pumpAndSettle();

          expect(find.byType(MaterialApp), findsOneWidget);
          expect(find.byType(MyHomePage), findsOneWidget);
          expect(find.text('HealthMAP'), findsOneWidget);
          expect(find.text('Explore Modules'), findsOneWidget);
          expect(find.text('News & Updates'), findsOneWidget);
          expect(find.text(alertText), findsOneWidget);
          expect(
              requests, [Uri.parse('https://example.invalid/alerts/latest')]);
          expect(unexpectedRequests, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }, () => client);
    });
  }
}
