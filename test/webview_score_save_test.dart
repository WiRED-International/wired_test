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
