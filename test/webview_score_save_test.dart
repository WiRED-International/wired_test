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
  @override
  dynamic noSuchMethod(Invocation invocation) {
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
        'module_name': 'Lesson',
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
