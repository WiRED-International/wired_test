import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
// Existing platform adapters let these tests avoid native PDF applications.
// ignore: depend_on_referenced_packages
import 'package:open_file_platform_interface/open_file_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wired_test/services/pending_quiz_score_repository.dart';
import 'package:wired_test/utils/webview_screen.dart';

class _PdfPaths extends PathProviderPlatform {
  _PdfPaths(this.path);
  final String path;
  @override
  Future<String?> getExternalStoragePath() async => path;
}

class _PdfOpener extends OpenFilePlatform {
  final paths = <String>[];
  @override
  Future<OpenResult> open(
    String? filePath, {
    String? type,
    bool isIOSAppOpen = false,
    String linuxDesktopName = 'xdg',
    bool linuxUseGio = false,
    bool linuxByProcess = false,
  }) async {
    paths.add(filePath!);
    return OpenResult(type: ResultType.done, message: 'done');
  }
}

class _Controller implements InAppWebViewController {
  WebUri? loadedUrl;
  Completer<WebUri?>? pendingUrl;
  var urlLookups = 0;
  @override
  Future<WebUri?> getUrl() async {
    urlLookups++;
    return pendingUrl == null ? loadedUrl : await pendingUrl!.future;
  }

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
  group('offline PDF resolution', () {
    late Directory root;
    late PathProviderPlatform originalPaths;
    late OpenFilePlatform originalOpener;
    late _PdfOpener opener;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('webview_pdf_resolution_');
      originalPaths = PathProviderPlatform.instance;
      originalOpener = OpenFilePlatform.platform;
      PathProviderPlatform.instance = _PdfPaths(root.path);
      opener = _PdfOpener();
      OpenFilePlatform.platform = opener;
    });

    tearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      OpenFilePlatform.platform = originalOpener;
      await root.delete(recursive: true);
    });

    testWidgets('pending PDF resolution does not open after disposal',
        (tester) async {
      final entry = File(p.join(root.path, 'module', 'index.html'));
      final pdf = File(p.join(entry.parent.path, 'guide.pdf'));
      await tester.runAsync(() async {
        await entry.parent.create(recursive: true);
        await entry.writeAsString('<html></html>');
        await pdf.writeAsString('%PDF-1.4 test fixture');
      });
      final platform = _Platform();
      final previous = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = platform;
      addTearDown(
          () => InAppWebViewPlatform.instance = previous ?? _Platform());
      await tester.pumpWidget(Provider.value(
        value: PendingQuizScoreRepository(
          read: () async => null,
          write: (_) async => fail('PDF routing must not save a score'),
        ),
        child: MaterialApp(
          home: WebViewScreen(
            moduleId: '1001',
            urlRequest: URLRequest(url: WebUri(entry.uri.toString())),
          ),
        ),
      ));
      final controller = _Controller()..pendingUrl = Completer<WebUri?>();
      final dynamic created = platform.params.onWebViewCreated;
      await created(controller);
      late Future<dynamic> request;
      await tester.runAsync(() async {
        request = controller.handlers['openPdfResource']!([
          {'file': 'guide.pdf', 'url': 'guide.pdf'}
        ]);
      });
      expect(controller.urlLookups, 1);
      expect(controller.pendingUrl!.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        controller.pendingUrl!.complete(WebUri(entry.uri.toString()));
        await request;
      });
      expect(opener.paths, isEmpty);
      expect(tester.takeException(), isNull);
    });

    // Characterizations preserve working paths; desired-behavior cases cover
    // the previously failing installation layouts.
    for (final scenario in [
      (
        name: 'characterization: absolute Storyline console URL',
        entry: 'files/1001/story.html',
        pdf: 'files/1001/story_content/external_files/guide.pdf',
        id: '1001',
        route: 'absolute'
      ),
      (
        name: 'characterization: friendly-folder compiler bridge',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/guide.pdf',
        id: '1001',
        route: 'bridge'
      ),
      (
        name: 'characterization: absolute legacy-package console URL',
        entry: 'packages/files/2024/1001/story.html',
        pdf: 'packages/files/2024/1001/story_content/external_files/guide.pdf',
        id: '1001',
        route: 'absolute'
      ),
      (
        name: 'desired: standalone Storyline bridge uses installed folder',
        entry: 'files/1001/story.html',
        pdf: 'files/1001/story_content/external_files/guide.pdf',
        id: '1001',
        route: 'bridge'
      ),
      (
        name: 'desired: compiler console path uses document folder, not ID',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/guide.pdf',
        id: '1001',
        route: 'relative'
      ),
      (
        name: 'desired: prefixed console URL resolves installed PDF',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/guide.pdf',
        id: '1001',
        route: 'prefixed'
      ),
      (
        name: 'desired: numeric compiler folder remains a compiler folder',
        entry: 'modules/1001/index.html',
        pdf: 'modules/1001/assets/resources/guide.pdf',
        id: '1001',
        route: 'bridge'
      ),
      (
        name: 'desired: legacy-package relative path uses document folder',
        entry: 'packages/files/2024/1001/story.html',
        pdf: 'packages/files/2024/1001/story_content/external_files/guide.pdf',
        id: '1001',
        route: 'relative'
      ),
      (
        name: 'redirected Storyline bridge uses current URL, not launcher',
        entry: 'files/Story Folder/story.html',
        pdf: 'files/Story Folder/story_content/external_files/guide.pdf',
        id: '1001',
        route: 'redirectBridge'
      ),
      (
        name: 'nested Storyline PDF paths retain directories and spaces',
        entry: 'files/1001/story.html',
        pdf: 'files/1001/story_content/external_files/nested/Study Guide.pdf',
        id: '1001',
        route: 'relative'
      ),
      (
        name: 'nested compiler bridge paths retain directories and spaces',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/nested/Study Guide.pdf',
        id: '1001',
        route: 'bridge'
      ),
      (
        name: 'reject traversal into another installed module',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Other/assets/resources/guide.pdf',
        id: '1001',
        route: 'rejectTraversal'
      ),
      (
        name: 'bare Storyline bridge filename uses local resource directory',
        entry: 'files/1001/story.html',
        pdf: 'files/1001/story_content/external_files/guide.pdf',
        id: '1001',
        route: 'bareBridge'
      ),
      (
        name: 'bare compiler bridge filename uses local resource directory',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/guide.pdf',
        id: '1001',
        route: 'bareBridge'
      ),
      (
        name: 'encoded nested filename and current document fragment work',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/nested/Study Guide.pdf',
        id: '1001',
        route: 'encodedRelative'
      ),
      (
        name: 'injected click-listener prefix resolves installed PDF',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/guide.pdf',
        id: '1001',
        route: 'injectedPrefix'
      ),
      (
        name: 'unknown console prefix is not stripped',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Friendly Lesson/assets/resources/guide.pdf',
        id: '1001',
        route: 'rejectUnknownPrefix'
      ),
      (
        name: 'reject percent-encoded traversal into another module',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Other/assets/resources/guide.pdf',
        id: '1001',
        route: 'rejectEncodedTraversal'
      ),
      (
        name: 'reject percent-encoded backslash traversal',
        entry: 'modules/Friendly Lesson/index.html',
        pdf: 'modules/Other/assets/resources/guide.pdf',
        id: '1001',
        route: 'rejectBackslashTraversal'
      ),
      (
        name: 'missing current URL does not guess from numeric ID',
        entry: 'modules/1001/index.html',
        pdf: 'modules/1001/assets/resources/guide.pdf',
        id: '1001',
        route: 'rejectMissingUrl'
      ),
    ]) {
      testWidgets(scenario.name, (tester) async {
        final entry = File(p.join(root.path, scenario.entry));
        final pdf = File(p.join(root.path, scenario.pdf));
        await tester.runAsync(() async {
          await entry.parent.create(recursive: true);
          await entry.writeAsString('<html></html>');
          await pdf.parent.create(recursive: true);
          await pdf.writeAsString('%PDF-1.4 test fixture');
        });
        final platform = _Platform();
        final previous = InAppWebViewPlatform.instance;
        InAppWebViewPlatform.instance = platform;
        addTearDown(
            () => InAppWebViewPlatform.instance = previous ?? _Platform());
        await tester.pumpWidget(Provider.value(
          value: PendingQuizScoreRepository(
            read: () async => null,
            write: (_) async => fail('PDF routing must not save a score'),
          ),
          child: MaterialApp(
              home: WebViewScreen(
            moduleId: scenario.id,
            urlRequest: URLRequest(
                url: WebUri(
              scenario.route == 'redirectBridge'
                  ? File(p.join(root.path, 'modules', 'launcher.htm'))
                      .uri
                      .toString()
                  : entry.uri.toString(),
            )),
          )),
        ));
        final controller = _Controller();
        controller.loadedUrl = scenario.route == 'rejectMissingUrl'
            ? null
            : WebUri(
                '${entry.uri}${scenario.route == 'encodedRelative' ? '#slide-1' : ''}');
        controller.nameLookup.complete(scenario.id);
        final dynamic created = platform.params.onWebViewCreated;
        await created(controller);
        final relative = p.posix
            .relative(scenario.pdf, from: p.posix.dirname(scenario.entry));
        await tester.runAsync(() async {
          if (scenario.route == 'bridge' ||
              scenario.route == 'redirectBridge' ||
              scenario.route == 'bareBridge') {
            await controller.handlers['openPdfResource']!([
              {
                'file': 'guide.pdf',
                'url': scenario.route == 'bareBridge' ? '' : relative
              }
            ]);
          } else {
            final dynamic console = platform.params.onConsoleMessage;
            final message = switch (scenario.route) {
              'absolute' => pdf.uri.toString(),
              'prefixed' => 'Link clicked: ${pdf.uri}',
              'injectedPrefix' => '🔗 Link clicked: $relative',
              'encodedRelative' => relative.replaceAll(' ', '%20'),
              'rejectUnknownPrefix' => 'Other message: ${pdf.uri}',
              'rejectEncodedTraversal' => relative.replaceAll('..', '%2e%2e'),
              'rejectBackslashTraversal' =>
                relative.replaceAll('../', '%2e%2e%5c'),
              _ => relative,
            };
            await console(controller, ConsoleMessage(message: message));
          }
        });
        expect(
            opener.paths.map(p.normalize).toList(),
            scenario.route.startsWith('reject')
                ? isEmpty
                : [p.normalize(pdf.path)],
            reason:
                'Only resources inside the current module may be resolved.');
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('Storyline score with .pdf metadata is saved as a quiz result',
      (tester) async {
    final platform = _Platform();
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform;
    addTearDown(() => InAppWebViewPlatform.instance = previous ?? _Platform());
    String? raw;
    final repository = PendingQuizScoreRepository(
      read: () async => raw,
      write: (value) async => raw = value,
    );
    await tester.pumpWidget(Provider.value(
      value: repository,
      child: MaterialApp(
          home: WebViewScreen(
        moduleId: '1234',
        urlRequest: URLRequest(url: WebUri('https://example.invalid')),
      )),
    ));
    final controller = _Controller();
    // Let an incorrect PDF route finish without invoking native file APIs.
    controller.nameLookup.complete('');
    final dynamic created = platform.params.onWebViewCreated;
    await created(controller);
    final dynamic console = platform.params.onConsoleMessage;
    await console(
        controller,
        ConsoleMessage(
            message: jsonEncode({
          'module_id': '1234',
          'module_name': 'Understanding .pdf resources',
          'quiz_score': 95,
        })));

    final scores = await repository.readAll();
    expect(scores['1234'], isNotNull,
        reason: 'Valid score metadata must not be routed as a PDF request.');
    expect(scores['1234']['score'], 95);
    expect(scores['1234']['module_name'], 'Understanding .pdf resources');
    expect(controller.nameLookups, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PDF console requests retain routing and malformed JSON saves nothing',
      (tester) async {
    final platform = _Platform();
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform;
    addTearDown(() => InAppWebViewPlatform.instance = previous ?? _Platform());
    String? raw;
    final repository = PendingQuizScoreRepository(
      read: () async => raw,
      write: (value) async => raw = value,
    );
    await tester.pumpWidget(Provider.value(
      value: repository,
      child: MaterialApp(
          home: WebViewScreen(
        moduleId: '1234',
        urlRequest: URLRequest(url: WebUri('https://example.invalid')),
      )),
    ));
    final controller = _Controller();
    // A missing current document URL prevents filesystem/native access.
    controller.nameLookup.complete('');
    final dynamic created = platform.params.onWebViewCreated;
    await created(controller);
    final dynamic console = platform.params.onConsoleMessage;
    for (final message in [
      'Link clicked: story_content/external_files/guide.pdf',
      'Link clicked: story_content/external_files/{guide}.pdf',
    ]) {
      final before = controller.urlLookups;
      await console(controller, ConsoleMessage(message: message));
      expect(controller.urlLookups, before + 1);
      expect(raw, isNull);
    }
    final before = controller.urlLookups;
    await console(controller,
        ConsoleMessage(message: '{"module_id":"1234","quiz_score":95,}'));
    expect(controller.urlLookups, before);
    expect(await repository.readAll(), isEmpty);
    expect(tester.takeException(), isNull);
  });

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
