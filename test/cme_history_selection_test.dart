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

class _OutputDirectory extends PathProviderPlatform {
  _OutputDirectory(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final year = DateTime.now().year;
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  List<Map<String, dynamic>> mixedYears() => [
        record('OldAlpha', year - 1, 2, id: 11),
        record('CurrentAlpha', year, 3, id: 12),
        record('OldBeta', year - 1, 1, id: 13),
        record('CurrentBeta', year, 1, id: 14),
        record('TrainingOnly', year, 4, id: 15, creditType: 'basic'),
      ];

  Future<void> withHistory(
      WidgetTester tester,
      List<Map<String, dynamic>> records,
      Future<void> Function(_ExportObserver observer) verify,
      {bool landscape = false}) async {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    addTearDown(dotenv.clean);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        landscape ? const Size(1600, 1000) : const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final output = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('cme_history_test_')))!;
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _OutputDirectory(output.path);
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      await output.delete(recursive: true);
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storage, (call) async {
      expect(call.method, 'read');
      expect((call.arguments as Map)['key'], 'authToken');
      return 'test-token';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(storage, null));
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.toString(), 'https://example.invalid/users/me');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response(jsonEncode({'id': 7, 'quizScores': records}), 200);
    });
    addTearDown(client.close);
    final observer = _ExportObserver();
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          navigatorObservers: [observer], home: const CreditsHistory()));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('TrainingOnly'), findsNothing);
      await verify(observer);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  }

  Future<void> chooseYear(WidgetTester tester, int? selectedYear) async {
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(selectedYear?.toString() ?? 'All Years').last);
    await tester.pumpAndSettle();
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

  testWidgets('portrait mixed-year list filters and sorts newest first',
      (tester) async {
    await withHistory(tester, mixedYears(), (_) async {
      expect(find.text('OldAlpha'), findsNothing);
      expect(find.text('OldBeta'), findsNothing);
      expect(tester.getTopLeft(find.text('CurrentAlpha')).dy,
          lessThan(tester.getTopLeft(find.text('CurrentBeta')).dy));
      await chooseYear(tester, year - 1);
      expect(find.text('CurrentAlpha'), findsNothing);
      expect(tester.getTopLeft(find.text('OldAlpha')).dy,
          lessThan(tester.getTopLeft(find.text('OldBeta')).dy));
    });
  });

  testWidgets('all-years export contains only the selected record',
      (tester) async {
    await withHistory(tester, mixedYears(), (observer) async {
      await chooseYear(tester, null);
      await select(tester, 'OldAlpha');
      final text = await export(tester, observer);
      expect(text, contains('OldAlpha'));
      for (final name in [
        'OldBeta',
        'CurrentAlpha',
        'CurrentBeta',
        'TrainingOnly'
      ]) {
        expect(text, isNot(contains(name)));
      }
    });
  });

  // Regressions reproduced against bda2413 before the selection mapping fix.
  testWidgets(
      'REGRESSION: first filtered row exports that record, not full-list index zero',
      (tester) async {
    await withHistory(tester, mixedYears(), (observer) async {
      await chooseYear(tester, year - 1);
      await select(tester, 'OldAlpha');
      final text = await export(tester, observer);
      expect(text, contains('OldAlpha'),
          reason: 'Export must use the selected record, not a full-list index');
      expect(text, isNot(contains('CurrentAlpha')));
    });
  });

  testWidgets('REGRESSION: Select All exports only the active year',
      (tester) async {
    await withHistory(tester, mixedYears(), (observer) async {
      await chooseYear(tester, year - 1);
      await tester.ensureVisible(find.text('Select All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();
      final text = await export(tester, observer);
      expect(text, contains('OldAlpha'));
      expect(text, contains('OldBeta'));
      expect(text, isNot(contains('CurrentAlpha')),
          reason: 'Select All must exclude hidden years');
      expect(text, isNot(contains('CurrentBeta')));
    });
  });

  testWidgets(
      'REGRESSION: switching years does not select another record by row position',
      (tester) async {
    await withHistory(tester, mixedYears(), (_) async {
      await select(tester, 'CurrentAlpha');
      await chooseYear(tester, year - 1);
      expect(
          find.descendant(
              of: checkbox('OldAlpha'), matching: find.byIcon(Icons.check)),
          findsNothing,
          reason: 'Selection must not transfer from CurrentAlpha to OldAlpha');
    });
  });

  testWidgets('REGRESSION: landscape applies the same year filter as portrait',
      (tester) async {
    await withHistory(tester, mixedYears(), (_) async {
      await chooseYear(tester, year - 1);
      expect(find.text('OldAlpha'), findsOneWidget);
      expect(find.text('CurrentAlpha'), findsNothing,
          reason: 'Landscape must apply selectedYear');
    }, landscape: true);
  });

  testWidgets('REGRESSION: rotation preserves the selected record',
      (tester) async {
    await withHistory(tester, mixedYears(), (observer) async {
      await select(tester, 'CurrentAlpha');
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      final text = await export(tester, observer);
      expect(text, contains('CurrentAlpha'),
          reason: 'Rotation must retain record identity');
      expect(text, isNot(contains('OldAlpha')));
    });
  });

  testWidgets('Select All after changing years replaces hidden selections',
      (tester) async {
    await withHistory(tester, mixedYears(), (observer) async {
      await select(tester, 'CurrentAlpha');
      await chooseYear(tester, year - 1);
      await tester.ensureVisible(find.text('Select All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();
      final text = await export(tester, observer);
      expect(text, contains('OldAlpha'));
      expect(text, contains('OldBeta'));
      expect(text, isNot(contains('CurrentAlpha')));
      expect(text, isNot(contains('CurrentBeta')));
      expect(text.indexOf('OldAlpha'), lessThan(text.indexOf('OldBeta')));
    });
  });

  testWidgets('export uses chronological order independent of selection order',
      (tester) async {
    await withHistory(tester, mixedYears(), (observer) async {
      await select(tester, 'CurrentBeta');
      await select(tester, 'CurrentAlpha');
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      final text = await export(tester, observer);
      expect(text.indexOf('CurrentAlpha'), greaterThanOrEqualTo(0));
      expect(text.indexOf('CurrentAlpha'), lessThan(text.indexOf('CurrentBeta')));
      expect(text, isNot(contains('OldAlpha')));
      expect(text, isNot(contains('OldBeta')));
    });
  });

  for (final duplicateIds in [false, true]) {
    testWidgets(
        'selection supports ${duplicateIds ? 'duplicate' : 'missing'} record IDs',
        (tester) async {
      await withHistory(tester, [
        record('FirstAttempt', year, 2, id: duplicateIds ? 9 : null),
        record('SecondAttempt', year, 1, id: duplicateIds ? 9 : null),
      ], (observer) async {
        await chooseYear(tester, null);
        await select(tester, 'SecondAttempt');
        final text = await export(tester, observer);
        expect(text, contains('SecondAttempt'));
        expect(text, isNot(contains('FirstAttempt')));
      });
    });
  }
}
