import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Test-only adapters use packages already resolved by path_provider/pdfviewer.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:wired_test/pages/cme/credits_history.dart';
import 'package:wired_test/utils/pdf_preview_screen.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/providers/auth_provider.dart';

class _OutputDirectory extends PathProviderPlatform {
  _OutputDirectory(this.path);
  String path;
  Completer<String?>? pending;
  Completer<void>? started;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (started != null && !started!.isCompleted) started!.complete();
    return pending == null ? path : await pending!.future;
  }
}

class _ExportObserver extends NavigatorObserver {
  Future<String>? exportedText;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    final page = route.builder(navigator!.context);
    expect(page, isA<PdfPreviewScreen>());
    final file = (page as PdfPreviewScreen).pdfFile;
    exportedText = () async {
      final document = PdfDocument(inputBytes: await file.readAsBytes());
      try {
        return PdfTextExtractor(document).extractText();
      } finally {
        document.dispose();
      }
    }();
    // Keep the native PDF viewer and email services out of these tests.
    Future<void>.microtask(() => navigator!.pop());
  }
}

// Fail synchronously at the navigation boundary, after the real PDF is written.
final navigationFailure = StateError('preview navigation failed');

class _FailingNavigator extends Navigator {
  _FailingNavigator()
      : super(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const CreditsHistory()));

  @override
  NavigatorState createState() => _FailingNavigatorState();
}

class _FailingNavigatorState extends NavigatorState {
  @override
  Future<T?> push<T extends Object?>(Route<T> route) {
    throw navigationFailure;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final year = DateTime.now().year;
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late AuthProvider auth;
  late _OutputDirectory paths;

  Map<String, dynamic> record(String name, int recordYear, int month,
          {int? id, String creditType = 'cme'}) =>
      {
        if (id != null) 'id': id,
        'module_id': 42,
        'score': 95,
        'date_taken':
            '$recordYear-${month.toString().padLeft(2, '0')}-01T12:00:00Z',
        'module': {
          'id': 42,
          'module_id': '1042',
          'name': name,
          'credit_type': creditType
        },
      };

  Future<void> withHistory(
      WidgetTester tester,
      List<Map<String, dynamic>> records,
      Future<void> Function(_ExportObserver observer) verify,
      {bool landscape = false,
      bool failNavigation = false}) async {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    addTearDown(dotenv.clean);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        landscape ? const Size(1600, 1000) : const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final output = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('cme_history_test_')))!;
    final originalPaths = PathProviderPlatform.instance;
    paths = _OutputDirectory(output.path);
    PathProviderPlatform.instance = paths;
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      await output.delete(recursive: true);
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final stored = <String, String>{};
    messenger.setMockMethodCallHandler(storage, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return stored[key];
        case 'write':
          stored[key] = args['value'] as String;
          return null;
        case 'delete':
          stored.remove(key);
          return null;
      }
      throw StateError('Unexpected storage operation');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(storage, null));
    auth = AuthProvider();
    await auth.logIn('A', DateTime.utc(2099));
    addTearDown(auth.dispose);
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.toString(), 'https://example.invalid/users/me');
      expect(request.headers['Authorization'], 'Bearer ${auth.authToken}');
      return http.Response(jsonEncode({'id': 7, 'quizScores': records}), 200);
    });
    addTearDown(client.close);
    final observer = _ExportObserver();
    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
              navigatorObservers: [observer],
              home: failNavigation
                  ? _FailingNavigator()
                  : const CreditsHistory())));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('TrainingOnly'), findsNothing);
      await verify(observer);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  }

  Finder checkbox(String name) => find.descendant(
        of: find
            .ancestor(of: find.text(name), matching: find.byType(Row))
            .first,
        matching: find.byType(InkWell),
      );

  Future<void> select(WidgetTester tester, String name) async {
    await tester.ensureVisible(checkbox(name));
    await tester.pumpAndSettle();
    await tester.tap(checkbox(name));
    await tester.pumpAndSettle();
  }

  Future<String> export(WidgetTester tester, _ExportObserver observer) async {
    await tester.ensureVisible(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Email')));
    for (var attempt = 0;
        attempt < 100 && observer.exportedText == null;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(observer.exportedText, isNotNull,
        reason: 'Actual export should reach PDF preview');
    final text = (await tester.runAsync(() => observer.exportedText!))!;
    await tester.pumpAndSettle();
    return text;
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(done(), isTrue,
        reason: 'Export must reach the controlled operation');
  }

  const failureMessage =
      'The PDF could not be created. Please try exporting again.';

  Future<void> settleExport(WidgetTester tester) async {
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
  }

  for (final landscape in [false, true]) {
    final layout = landscape ? 'landscape' : 'portrait';
    testWidgets('$layout navigation errors are not PDF creation failures',
        (tester) async {
      await withHistory(tester, [record('SelectedLesson', year, 3)],
          (observer) async {
        await select(tester, 'SelectedLesson');
        final button = tester.widget<ElevatedButton>(find.ancestor(
            of: find.text('Email'),
            matching:
                find.byWidgetPredicate((widget) => widget is ElevatedButton)));
        await tester.runAsync(() async {
          // Invoke the async callback directly so its navigation error is observed.
          final dynamic callback = button.onPressed!;
          await expectLater(callback(), throwsA(same(navigationFailure)));
          expect(await File('${paths.path}/cme_history.pdf').exists(), isTrue);
        });
        await tester.pumpAndSettle();
        expect(find.text(failureMessage), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(observer.exportedText, isNull);
      }, landscape: landscape, failNavigation: true);
    });

    for (final stage in ['asset', 'generation', 'directory', 'write']) {
      testWidgets('$layout $stage failure is friendly and export can retry',
          (tester) async {
        await withHistory(tester, [record('SelectedLesson', year, 3)],
            (observer) async {
          await select(tester, 'SelectedLesson');
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          final originalPath = paths.path;
          Completer<ByteData?>? asset;
          final reached = Completer<void>();
          if (stage == 'asset' || stage == 'generation') {
            asset = Completer<ByteData?>();
            messenger.setMockMessageHandler('flutter/assets', (message) {
              expect(utf8.decode(message!.buffer.asUint8List()),
                  'assets/images/watermark.png');
              reached.complete();
              return asset!.future;
            });
            addTearDown(
                () => messenger.setMockMessageHandler('flutter/assets', null));
          } else {
            paths.started = reached;
            paths.pending = Completer<String?>();
          }
          await tester.ensureVisible(find.text('Email'));
          await tester.runAsync(() async {
            await tester.tap(find.text('Email'));
          });
          await waitFor(tester, () => reached.isCompleted);
          if (stage == 'asset' || stage == 'generation') {
            await tester.runAsync(() async {
              asset!.complete(stage == 'asset' ? null : ByteData(4));
            });
          } else if (stage == 'directory') {
            await tester.runAsync(() async {
              paths.pending!
                  .completeError(StateError('private directory details'));
            });
          } else {
            // A regular file cannot serve as the output directory.
            await tester.runAsync(() async {
              final blocker = File('$originalPath/blocker');
              await blocker.writeAsString('not a directory');
              paths.pending!.complete(blocker.path);
            });
          }
          for (var i = 0;
              i < 100 && find.text(failureMessage).evaluate().isEmpty;
              i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 5)));
            await tester.pump();
          }
          expect(find.text(failureMessage), findsOneWidget);
          expect(find.byType(SnackBar), findsOneWidget);
          expect(
              find.textContaining('private directory details'), findsNothing);
          expect(find.textContaining('FileSystemException'), findsNothing);
          expect(observer.exportedText, isNull);
          expect(tester.takeException(), isNull);
          messenger.setMockMessageHandler('flutter/assets', null);
          paths.pending = null;
          paths.started = null;
          paths.path = originalPath;
          final text = await export(tester, observer);
          expect(text, contains('SelectedLesson'));
          expect(
              text.replaceAll(RegExp(r'\s+'), ' '), contains('Mar 01, $year'));
        }, landscape: landscape);
      });
    }

    for (final stage in ['asset', 'directory']) {
      for (final transition in ['dispose', 'switch', 'reuse']) {
        testWidgets('$layout $stage failure after $transition has no stale UI',
            (tester) async {
          await withHistory(tester, [record('SelectedLesson', year, 3)],
              (observer) async {
            await select(tester, 'SelectedLesson');
            final messenger = TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger;
            final reached = Completer<void>();
            Completer<ByteData?>? asset;
            if (stage == 'asset') {
              asset = Completer<ByteData?>();
              messenger.setMockMessageHandler('flutter/assets', (_) {
                reached.complete();
                return asset!.future;
              });
              addTearDown(() =>
                  messenger.setMockMessageHandler('flutter/assets', null));
            } else {
              paths.started = reached;
              paths.pending = Completer<String?>();
            }
            await tester.ensureVisible(find.text('Email'));
            await tester.runAsync(() async {
              await tester.tap(find.text('Email'));
            });
            await waitFor(tester, () => reached.isCompleted);
            if (transition == 'dispose') {
              await tester.pumpWidget(const SizedBox.shrink());
            } else {
              if (transition == 'reuse') await auth.logOut();
              await auth.logIn(
                  transition == 'reuse' ? 'A' : 'B', DateTime.utc(2099));
              await tester.pumpAndSettle();
            }
            await tester.runAsync(() async {
              if (stage == 'asset') {
                asset!.complete(null);
              } else {
                paths.pending!
                    .completeError(StateError('private late failure'));
              }
            });
            await settleExport(tester);
            expect(find.byType(SnackBar), findsNothing);
            expect(observer.exportedText, isNull);
            expect(tester.takeException(), isNull);
          }, landscape: landscape);
        });
      }
    }
  }
}
