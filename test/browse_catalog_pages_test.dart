import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/pages/byAlphabet/module_by_alphabet.dart';
import 'package:wired_test/pages/byTopic/topic_list.dart';
import 'package:wired_test/services/browse_catalog_repository.dart';

void main() {
  setUp(() => BrowseCatalogRepository.shared.clear());
  tearDown(() => BrowseCatalogRepository.shared.clear());
  for (final alphabet in [true, false]) {
    testWidgets(
        '${alphabet ? 'letters' : 'categories'} share catalog and force fresh retries',
        (tester) async {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      addTearDown(dotenv.clean);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.path, alphabet ? '/modules/' : '/subCategories');
        expect(request.url.query, '');
        if (requests == 2) return http.Response('Unavailable', 503);
        return http.Response(
            jsonEncode([
              for (final i in [1, 2])
                {
                  'id': 40 + i,
                  'module_id': '${140 + i}',
                  'name': '${i == 1 ? 'First' : 'Second'} result $requests',
                  'category_id': i,
                  'letters': [
                    {'letters': i == 1 ? 'A' : 'B'}
                  ]
                },
            ]),
            200);
      });
      addTearDown(client.close);
      Widget page(int selection) => alphabet
          ? ModuleByAlphabet(letter: selection == 1 ? 'A' : 'B')
          : TopicList(category: 'Category $selection', categoryId: selection);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                      body: Column(children: [
                        for (final selection in [1, 2])
                          TextButton(
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => page(selection))),
                              child: Text('Open $selection')),
                      ]),
                    ))));
        await tester.tap(find.text('Open 1'));
        await tester.pumpAndSettle();
        expect(find.text('First result 1'), findsOneWidget);
        expect(find.text('Second result 1'), findsNothing);
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open 2'));
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(find.text('Second result 1'), findsOneWidget);
        expect(find.text('First result 1'), findsNothing);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(find.text('Try Again'), findsOneWidget);

        // Another consumer refills the cache while this page shows an error.
        // Try Again must bypass even that fresh response.
        await BrowseCatalogRepository.shared.fetchListBody(
          Uri.parse(
              'https://example.invalid${alphabet ? '/modules/' : '/subCategories'}'),
          headers: alphabet
              ? const {'Content-Type': 'application/json; charset=utf-8'}
              : const {},
        );
        expect(requests, 3);
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();
        expect(requests, 4);
        expect(find.text('Second result 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    });
  }
}
