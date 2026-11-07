import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/models/downloadable_module.dart';
import 'package:wired_test/pages/byAlphabet/module_by_alphabet.dart';
import 'package:wired_test/pages/byTopic/module_by_topic.dart';
import 'package:wired_test/pages/module_details_page.dart';
import 'package:wired_test/widgets/browse/module_browse_card.dart';

Map<String, dynamic> _module(int id, String name) => {
      'id': id,
      'module_id': '${id + 1000}',
      'name': name,
      'description': 'Education about $name',
      'version': '2.3',
      'downloadLink': 'https://content.example.invalid/$id.zip',
      'packageSize': '12 MB',
      'credit_type': 'cme',
      'letters': [
        {'letters': ' a '},
      ],
      'programs': [
        {'id': 3, 'name': 'CHW Training', 'training_type': 'basic'},
      ],
      'keywords': [
        {'name': 'Prevention'},
      ],
      'subCategories': [
        {
          'id': 7,
          'name': 'Community Health',
          'category': {'id': 2, 'name': 'Health'},
        },
      ],
      'specializations': [
        {'name': 'Public Health'},
      ],
    };

Map<String, dynamic> _alias(int id, String name, Map<String, dynamic> target) =>
    {
      ..._module(id, name),
      'redirectedModule': target,
    };

// Capture the real route's argument and pop before plugin-backed Details mounts.
// This follows the navigation observer pattern in program_modules_page_test.dart.
class _DetailsObserver extends NavigatorObserver {
  final modules = <DownloadableModule>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    final page = route.builder(navigator!.context);
    expect(page, isA<ModuleDetailsPage>());
    modules.add((page as ModuleDetailsPage).module);
    Future<void>.microtask(() => navigator!.pop());
  }
}

void main() {
  for (final alphabet in [true, false]) {
    final pageName = alphabet ? 'alphabet' : 'topic';

    Future<void> withCatalog(
      WidgetTester tester,
      Object? catalog,
      Future<void> Function(_DetailsObserver observer) verify,
    ) async {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      addTearDown(dotenv.clean);
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final observer = _DetailsObserver();
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(request.url.host, 'example.invalid');
        expect(request.url.path, alphabet ? '/modules/' : '/modules');
        expect(request.url.queryParameters,
            alphabet ? <String, String>{} : {'subcategoryId': '7'});
        return http.Response(jsonEncode(catalog), 200);
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          navigatorObservers: [observer],
          home: alphabet
              ? const ModuleByAlphabet(letter: ' a ')
              : const ModuleByTopic(
                  subcategoryName: 'Community Health', subcategoryId: 7),
        ));
        await tester.pumpAndSettle();
        expect(requests, 1);
        await verify(observer);
        // Returning from captured Details routes must not reload the catalog.
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    }

    Future<DownloadableModule> openCard(
        WidgetTester tester, _DetailsObserver observer, Finder card) async {
      await tester.ensureVisible(card);
      final previousCount = observer.modules.length;
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(observer.modules.length, previousCount + 1);
      return observer.modules.last;
    }

    testWidgets(
        '$pageName preserves aliases, alias sorting and target metadata',
        (tester) async {
      final target = _module(42, 'Zoonotic Disease');
      await withCatalog(tester, [
        _alias(903, 'zebra exposure', target),
        _module(43, 'Middle Health'),
        _alias(901, 'Animal Bites', target),
        _alias(902, 'bee stings', target),
      ], (observer) async {
        final cards = tester
            .widgetList<ModuleBrowseCard>(find.byType(ModuleBrowseCard))
            .toList();
        expect(cards.map((card) => card.redirectFrom ?? card.title),
            ['Animal Bites', 'bee stings', 'Middle Health', 'zebra exposure']);
        expect(
            cards.where((card) => card.title == 'Zoonotic Disease').length, 3);
        for (final alias in ['Animal Bites', 'bee stings', 'zebra exposure']) {
          final card = find.byWidgetPredicate((widget) =>
              widget is ModuleBrowseCard && widget.redirectFrom == alias);
          expect(
              find.descendant(
                  of: card, matching: find.text('$alias · See also')),
              findsOneWidget);
          final module = await openCard(tester, observer, card);
          expect(module.id, 42);
          expect(module.moduleId, '1042');
          expect(module.name, 'Zoonotic Disease');
          expect(module.description, 'Education about Zoonotic Disease');
          expect(module.version, '2.3');
          expect(module.downloadLink, 'https://content.example.invalid/42.zip');
          expect(module.packageSize, '12 MB');
          expect(module.creditType, 'cme');
          expect(module.programs.single.id, 3);
          expect(module.programs.single.trainingType, 'basic');
          expect(module.keywords, ['Prevention']);
          expect(module.categories, ['Health']);
          expect(module.subcategories, ['Community Health']);
          expect(module.specializations, ['Public Health']);
        }
        final direct = await openCard(tester, observer,
            find.widgetWithText(ModuleBrowseCard, 'Middle Health'));
        expect(direct.id, 43);
        expect(direct.moduleId, '1043');
      });
    });

    for (final legacy in ['missing', 'blank', 'null']) {
      testWidgets('$pageName $legacy module_id falls back to target id',
          (tester) async {
        final target = _module(77, 'Legacy Target');
        if (legacy == 'missing') {
          target.remove('module_id');
        } else {
          target['module_id'] = legacy == 'blank' ? '   ' : null;
        }
        final direct = {...target, 'id': 78, 'name': 'Legacy Direct'};
        await withCatalog(tester, [
          _alias(999, 'Alias to legacy target', target),
          direct,
        ], (observer) async {
          final redirected = await openCard(tester, observer,
              find.widgetWithText(ModuleBrowseCard, 'Legacy Target'));
          expect(redirected.id, 77);
          expect(redirected.moduleId, '77');
          final module = await openCard(tester, observer,
              find.widgetWithText(ModuleBrowseCard, 'Legacy Direct'));
          expect(module.id, 78);
          expect(module.moduleId, '78');
        });
      });
    }

    testWidgets(
        '$pageName skips nonmaps and blank names but keeps incomplete modules',
        (tester) async {
      await withCatalog(tester, [
        null,
        12,
        'bad row',
        {..._module(2, '   ')},
        _alias(900, 'Alias with blank target', _module(3, '')),
        {
          'name': 'Incomplete module',
          'letters': [
            {'letters': 'A'}
          ]
        },
        {..._module(4, 'Non-map redirect'), 'redirectedModule': 'invalid'},
      ], (observer) async {
        expect(find.byType(ModuleBrowseCard), findsNWidgets(2));
        final incomplete = await openCard(tester, observer,
            find.widgetWithText(ModuleBrowseCard, 'Incomplete module'));
        expect(incomplete.id, isNull);
        expect(incomplete.moduleId, '');
        expect(incomplete.downloadLink, isNull);
        expect(incomplete.isDownloadable, isFalse);
        final direct = await openCard(tester, observer,
            find.widgetWithText(ModuleBrowseCard, 'Non-map redirect'));
        expect(direct.id, 4);
        expect(direct.moduleId, '1004');
      });
    });

    testWidgets('$pageName malformed nested programs fails the complete result',
        (tester) async {
      await withCatalog(tester, [
        _module(1, 'Valid module'),
        {..._module(2, 'Malformed module'), 'programs': 'not a list'},
      ], (_) async {
        expect(find.text('Unable to load modules'), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.byType(ModuleBrowseCard), findsNothing);
      });
    });

    testWidgets('$pageName non-list response fails instead of becoming empty',
        (tester) async {
      await withCatalog(tester, {'modules': []}, (_) async {
        expect(find.text('Unable to load modules'), findsOneWidget);
        expect(find.text('No modules found'), findsNothing);
      });
    });

    if (alphabet) {
      testWidgets('alphabet uses original letters before resolving redirects',
          (tester) async {
        await withCatalog(tester, [
          _alias(900, 'Animal alias', {
            ..._module(42, 'Target with B association'),
            'letters': [
              {'letters': 'B'}
            ],
          }),
          {
            ..._alias(901, 'Excluded B alias',
                _module(43, 'Target with A association')),
            'letters': [
              {'letters': 'B'}
            ]
          },
          {..._module(44, 'No letter field')}..remove('letters'),
          {..._module(45, 'Non-list letters'), 'letters': 'A'},
        ], (observer) async {
          expect(find.byType(ModuleBrowseCard), findsOneWidget);
          final target = await openCard(
              tester,
              observer,
              find.widgetWithText(
                  ModuleBrowseCard, 'Target with B association'));
          expect(target.id, 42);
          expect(target.moduleId, '1042');
          expect(find.text('Target with A association'), findsNothing);
        });
      });

      testWidgets('alphabet malformed nested letter fails the complete result',
          (tester) async {
        await withCatalog(tester, [
          _module(1, 'Valid module'),
          {
            ..._module(2, 'Invalid letters'),
            'letters': [null]
          },
        ], (_) async {
          expect(find.text('Unable to load modules'), findsOneWidget);
          expect(find.byType(ModuleBrowseCard), findsNothing);
        });
      });
    } else {
      testWidgets(
          'topic trusts server filtering without requiring letter metadata',
          (tester) async {
        await withCatalog(tester, [
          _module(42, 'No letters needed')..remove('letters'),
        ], (observer) async {
          final module = await openCard(tester, observer,
              find.widgetWithText(ModuleBrowseCard, 'No letters needed'));
          expect(module.id, 42);
          expect(module.moduleId, '1042');
        });
      });
    }
  }
}
