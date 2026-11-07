import 'package:wired_test/services/browse_catalog_repository.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/pages/byAlphabet/module_by_alphabet.dart';
import 'package:wired_test/pages/byTopic/by_topic.dart';
import 'package:wired_test/pages/byTopic/module_by_topic.dart';

void main() {
  setUp(() => BrowseCatalogRepository.shared.clear());
  tearDown(() => BrowseCatalogRepository.shared.clear());
  final cases = [
    (
      name: 'alphabet modules',
      page: () => const ModuleByAlphabet(letter: 'A'),
      endpoint: '/modules/',
      query: <String, String>{},
      emptyText: 'No modules found',
    ),
    (
      name: 'topics',
      page: () => const ByTopic(),
      endpoint: '/categories',
      query: <String, String>{},
      emptyText: 'No topics available',
    ),
    (
      name: 'topic modules',
      page: () => const ModuleByTopic(
            subcategoryName: 'Health',
            subcategoryId: 7,
          ),
      endpoint: '/modules',
      query: {'subcategoryId': '7'},
      emptyText: 'No modules found',
    ),
  ];

  for (final scenario in cases) {
    for (final initialCount in [0, 1]) {
      testWidgets('${scenario.name} refreshes a $initialCount-item list once',
          (tester) async {
        dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
        addTearDown(dotenv.clean);
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var requestCount = 0;
        Map<String, Object> item(String name) => {
              'id': 42,
              'module_id': '142',
              'name': name,
              'letters': [
                {'letters': 'A'},
              ],
            };
        final client = MockClient((request) async {
          requestCount++;
          expect(request.method, 'GET');
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'example.invalid');
          expect(request.url.path, scenario.endpoint);
          expect(request.url.queryParameters, scenario.query);
          return http.Response(
              jsonEncode(requestCount == 1
                  ? [if (initialCount == 1) item('A initial result')]
                  : [item('A updated result $requestCount')]),
              200);
        });
        addTearDown(client.close);

        await http.runWithClient(() async {
          Widget app() => MaterialApp(
                theme: ThemeData(platform: TargetPlatform.android),
                home: scenario.page(),
              );
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          expect(requestCount, 1);
          expect(find.text(initialCount == 0
              ? scenario.emptyText
              : 'A initial result'), findsOneWidget);

          // Recreate widget configurations while retaining the page's State.
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          expect(requestCount, 1);

          final scrollView = find.byType(CustomScrollView);
          final scrollable = tester.state<ScrollableState>(find.descendant(
            of: scrollView,
            matching: find.byType(Scrollable),
          ));
          expect(scrollable.position.maxScrollExtent, 0);

          // Exercise the real gesture, rather than invoking onRefresh directly.
          for (final expectedRequests in [2, 3]) {
            await tester.drag(scrollView, const Offset(0, 400));
            await tester.pumpAndSettle();
            expect(requestCount, expectedRequests);
            expect(find.text('A updated result $expectedRequests'),
                findsOneWidget);
            expect(find.text('A initial result'), findsNothing);
            await tester.pumpWidget(app());
            await tester.pumpAndSettle();
            expect(requestCount, expectedRequests);
          }

          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => client);
      });
    }
  }
}
