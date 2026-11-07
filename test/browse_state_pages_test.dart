import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/pages/byAlphabet/module_by_alphabet.dart';
import 'package:wired_test/pages/byTopic/by_topic.dart';
import 'package:wired_test/pages/byTopic/topic_list.dart';
import 'package:wired_test/pages/byTopic/module_by_topic.dart';

void main() {
  final cases = [
    (
      page: () => const ModuleByAlphabet(letter: 'A'),
      path: '/modules/',
      query: <String, String>{},
      error: 'Unable to load modules',
      empty: 'No modules found',
      detail: 'There are no modules listed under this letter.',
      errorDetail: 'Check your connection and try again.',
      color: null
    ),
    (
      page: () => const ByTopic(),
      path: '/categories',
      query: <String, String>{},
      error: 'Unable to load topics',
      empty: 'No topics available',
      detail: 'There are no topics to display right now.',
      errorDetail: 'Check your connection and try again.',
      color: null
    ),
    (
      page: () => const TopicList(category: 'Health', categoryId: 7),
      path: '/subCategories',
      query: <String, String>{},
      error: 'Unable to load subtopics',
      empty: 'No subtopics available',
      detail: 'There are no subtopics listed under this category.',
      errorDetail: 'Check your internet connection and try again.',
      color: const Color(0xFF0070C0)
    ),
    (
      page: () =>
          const ModuleByTopic(subcategoryName: 'Health', subcategoryId: 7),
      path: '/modules',
      query: {'subcategoryId': '7'},
      error: 'Unable to load modules',
      empty: 'No modules found',
      detail: 'There are no modules listed under this subtopic.',
      errorDetail: 'Check your connection and try again.',
      color: null
    ),
  ];

  for (final scenario in cases) {
    testWidgets('${scenario.path} ${scenario.query} loading, empty and retry',
        (tester) async {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      addTearDown(dotenv.clean);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final responses = List.generate(3, (_) => Completer<http.Response>());
      var requests = 0;
      final client = MockClient((request) {
        expect(request.method, 'GET');
        expect(request.url.host, 'example.invalid');
        expect(request.url.path, scenario.path);
        expect(request.url.queryParameters, scenario.query);
        return responses[requests++].future;
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: scenario.page()));
        await tester.pump();
        expect(requests, 1);
        expect(
            tester
                .widget<CircularProgressIndicator>(
                    find.byType(CircularProgressIndicator))
                .color,
            scenario.color);
        expect(find.text('Try Again'), findsNothing);
        responses[0].complete(http.Response('[]', 200));
        await tester.pumpAndSettle();
        expect(find.text(scenario.empty), findsOneWidget);
        expect(find.text(scenario.detail), findsOneWidget);
        expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
        expect(find.text('Try Again'), findsNothing);

        await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(requests, 2);
        responses[1].complete(http.Response('Unavailable', 503));
        await tester.pumpAndSettle();
        expect(find.text(scenario.error), findsOneWidget);
        expect(find.text(scenario.errorDetail), findsOneWidget);
        expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

        await tester.tap(find.text('Try Again'));
        await tester.pump();
        expect(requests, 3);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        responses[2].complete(http.Response(
            jsonEncode([
              {
                'id': 42,
                'module_id': '142',
                'name': 'A recovered result',
                'category_id': 7,
                'letters': [
                  {'letters': 'A'}
                ]
              },
            ]),
            200));
        await tester.pumpAndSettle();
        expect(find.text('A recovered result'), findsOneWidget);
        expect(find.text('Try Again'), findsNothing);
        expect(requests, 3);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    });
  }
}
