import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wired_test/main.dart';
import 'package:wired_test/pages/home_page.dart';

void main() {
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
