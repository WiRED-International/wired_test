import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/services/pending_quiz_score_repository.dart';
import 'package:wired_test/utils/webview_screen.dart';

class _Controller implements InAppWebViewController {
  final Map<String, Function> handlers = {};
  final nameLookup = Completer<String>();
  var nameLookups = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #evaluateJavascript) {
      nameLookups++;
      return nameLookup.future;
    }
    if (invocation.memberName == #addJavaScriptHandler) {
      handlers[invocation.namedArguments[#handlerName] as String] =
          invocation.namedArguments[#callback] as Function;
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _View extends PlatformInAppWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Platform extends InAppWebViewPlatform {
  late PlatformInAppWebViewWidgetCreationParams params;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams value) {
    params = value;
    return _View(value);
  }
}

void main() {
  testWidgets('Storyline resolves friendly names synchronously',
      (tester) async {
    final platform = _Platform();
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform;
    addTearDown(() => InAppWebViewPlatform.instance = previous ?? _Platform());
    for (final launchName in ['Library lesson', null, '   ']) {
      String? raw;
      final repository = PendingQuizScoreRepository(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      await tester.pumpWidget(Provider.value(
        value: repository,
        child: MaterialApp(
            home: WebViewScreen(
          key: UniqueKey(),
          moduleId: '00123456',
          moduleName: launchName,
          urlRequest: URLRequest(url: WebUri('https://example.invalid')),
        )),
      ));
      final controller = _Controller();
      final dynamic created = platform.params.onWebViewCreated;
      await created(controller);
      final dynamic console = platform.params.onConsoleMessage;
      for (final messageName in [null, '', '   ', 42, 'Message lesson']) {
        await console(
            controller,
            ConsoleMessage(
                message: jsonEncode({
              'module_id': '00123456',
              'quiz_score': 0,
              if (messageName != null) 'module_name': messageName,
            })));
        final entry = (jsonDecode(raw!) as Map)['00123456'];
        expect(
            entry['module_name'],
            messageName == 'Message lesson'
                ? messageName
                : launchName == 'Library lesson'
                    ? launchName
                    : 'Unknown Module');
        expect(entry['score'], 0);
      }
      expect(controller.nameLookups, 0);
    }
    expect(tester.takeException(), isNull);
  });

  for (final newerScore in [95, 80]) {
    testWidgets('Storyline retakes preserve arrival order: $newerScore',
        (tester) async {
      String? raw;
      final saved = <Map>[];
      final firstWrite = Completer<void>();
      final releaseWrite = Completer<void>();
      final repository = PendingQuizScoreRepository(
        read: () async => raw,
        write: (value) async {
          if (!firstWrite.isCompleted) {
            firstWrite.complete();
            await releaseWrite.future;
          }
          raw = value;
          saved.add((jsonDecode(value) as Map)['1234'] as Map);
        },
      );
      final platform = _Platform();
      final previous = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = platform;
      addTearDown(
          () => InAppWebViewPlatform.instance = previous ?? _Platform());
      await tester.pumpWidget(Provider.value(
        value: repository,
        child: MaterialApp(
            home: WebViewScreen(
          moduleId: '1234',
          moduleName: 'Library lesson',
          urlRequest: URLRequest(url: WebUri('https://example.invalid')),
        )),
      ));
      final controller = _Controller();
      final dynamic created = platform.params.onWebViewCreated;
      await created(controller);
      final dynamic console = platform.params.onConsoleMessage;
      final Future<dynamic> older = console(controller,
          ConsoleMessage(message: '{"module_id":"1234","quiz_score":80}'));
      final Future<dynamic> newer = console(
          controller,
          ConsoleMessage(
              message: jsonEncode({
            'module_id': '1234',
            'quiz_score': newerScore,
            'module_name': 'Newer lesson'
          })));
      // On the old implementation A waits here while B enters storage first.
      await firstWrite.future;
      controller.nameLookup.complete('Delayed older name');
      releaseWrite.complete();
      await Future.wait([older, newer]);
      expect(saved.map((entry) => entry['module_name']),
          ['Library lesson', 'Newer lesson']);
      expect(saved.map((entry) => entry['score']), [80, newerScore]);
      expect((jsonDecode(raw!) as Map)['1234']['module_name'], 'Newer lesson');
      expect(controller.nameLookups, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final compiler in [true, false]) {
    testWidgets(
        '${compiler ? "compiler" : "Storyline"} validates incoming results without losing saved scores',
        (tester) async {
      var raw = '{"1234":{"module_name":"Lesson","score":80}}';
      var writes = 0;
      final repository = PendingQuizScoreRepository(
          read: () async => raw,
          write: (value) async {
            writes++;
            raw = value;
          });
      final platform = _Platform();
      final previous = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = platform;
      addTearDown(
          () => InAppWebViewPlatform.instance = previous ?? _Platform());
      await tester.pumpWidget(Provider.value(
          value: repository,
          child: MaterialApp(
              home: WebViewScreen(
                  moduleId: '1234',
                  urlRequest:
                      URLRequest(url: WebUri('https://example.invalid'))))));
      final controller = _Controller();
      final dynamic created = platform.params.onWebViewCreated;
      await created(controller);
      Future<void> send(Map<String, dynamic> data) async {
        if (compiler) {
          await controller.handlers['saveCmeScore']!([data]);
        } else {
          final dynamic console = platform.params.onConsoleMessage;
          await console(controller, ConsoleMessage(message: jsonEncode(data)));
        }
        await tester.pump();
      }

      for (final value in [0, 0.0, 12.5, 80, 100, '0', '75.5']) {
        await send({
          'module_id': '1234',
          'module_name': 'Lesson',
          'quiz_score': value
        });
        expect((jsonDecode(raw) as Map)['1234']['score'],
            double.parse(value.toString()));
      }
      // Keep nonfinite values as strings for the JSON-based Storyline bridge.
      for (final value in [
        null,
        '',
        'bad',
        -1,
        100.1,
        'NaN',
        'Infinity',
        '-Infinity',
        false,
        [],
        {}
      ]) {
        final before = raw;
        final count = writes;
        await send({
          'module_id': '1234',
          'module_name': 'Lesson',
          if (value != null) 'quiz_score': value
        });
        expect(raw, before);
        expect(writes, count);
        expect(find.textContaining('Your quiz result could not be saved'),
            findsOneWidget);
      }
      for (final id in [
        null,
        '',
        'unknown',
        'abc',
        '../1234',
        0,
        '0000',
        -1,
        false,
        []
      ]) {
        final before = raw;
        final count = writes;
        await send({
          if (id != null) 'module_id': id,
          'module_name': 'Lesson',
          'quiz_score': 95
        });
        expect(raw, before);
        expect(writes, count);
      }
      if (compiler) {
        for (final value in [
          double.nan,
          double.infinity,
          double.negativeInfinity
        ]) {
          final before = raw;
          await send({'module_id': '1234', 'quiz_score': value});
          expect(raw, before);
        }
      }
      await send({
        'module_id': '00123456',
        'module_name': 'Compiler lesson',
        'quiz_score': 0
      });
      expect((jsonDecode(raw) as Map)['00123456']['score'], 0);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        '${compiler ? "compiler" : "Storyline"} save failure preserves prior result and recovers',
        (tester) async {
      var raw = '{"1234":{"module_name":"Lesson","score":80}}';
      final original = raw;
      var fail = true;
      final repository = PendingQuizScoreRepository(
        read: () async => raw,
        write: (value) async {
          if (fail) throw StateError('storage write failed');
          raw = value;
        },
      );
      final platform = _Platform();
      final previousPlatform = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = platform;
      addTearDown(() =>
          InAppWebViewPlatform.instance = previousPlatform ?? _Platform());
      await tester.pumpWidget(Provider.value(
        value: repository,
        child: MaterialApp(
            home: WebViewScreen(
          moduleId: '1234',
          urlRequest: URLRequest(url: WebUri('https://example.invalid')),
        )),
      ));
      final controller = _Controller();
      final dynamic created = platform.params.onWebViewCreated;
      await created(controller);
      final data = {
        'module_id': '1234',
        if (compiler) 'module_name': 'Lesson',
        'quiz_score': 95
      };
      Future<void> save() async {
        if (compiler) {
          await controller.handlers['saveCmeScore']!([data]);
        } else {
          final dynamic console = platform.params.onConsoleMessage;
          await console(controller, ConsoleMessage(message: jsonEncode(data)));
        }
      }

      final logs = <String>[];
      await runZoned(() => save(),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, message) => logs.add(message),
          ));
      await tester.pump();
      expect(raw, original);
      expect(find.textContaining('Your quiz result could not be saved'),
          findsOneWidget);
      expect(
          logs.where(
              (line) => line.contains('Compiler score saved successfully')),
          isEmpty);
      fail = false;
      await save();
      expect((jsonDecode(raw) as Map)['1234']['score'], 95);
      expect(tester.takeException(), isNull);
    });
  }
}
