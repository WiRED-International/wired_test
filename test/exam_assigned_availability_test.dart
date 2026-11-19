import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/models/user.dart';
import 'package:wired_test/pages/exam/exam_page.dart';
import 'package:wired_test/pages/exam/exam_start.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

// No Hive, secure storage, backend, timers, or synchronization are used here.
class _UnusedBox<T> implements Box<T> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected persistence call: ${invocation.memberName}');
}

class _AssignedAdapter implements HttpClientAdapter {
  Object payload = <Object>[];
  final requests = <RequestOptions>[];
  int statusCode = 200;
  Completer<void>? pending;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await pending?.future;
    if (options.method != 'GET' || options.path != '/exams/assigned') {
      throw StateError('Unexpected request: ${options.method} ${options.path}');
    }
    return ResponseBody.fromString(
      payload is String ? payload as String : jsonEncode(payload),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Controller extends ChangeNotifier implements ExamController {
  int restores = 0;
  int starts = 0;
  final startedIds = <int>[];
  List<Map<String, dynamic>>? questions;
  @override
  int? savedExamId;
  @override
  int remainingSeconds = 0;

  @override
  Future<void> restoreExamIfExists() async {
    restores++;
  }

  @override
  Future<List<Map<String, dynamic>>?> startExam({
    required int examId,
    required int userId,
  }) async {
    starts++;
    startedIds.add(examId);
    return questions;
  }

  final recoveries = <int, ExamRecoveryState>{};
  @override
  ExamRecoveryState recoveryStateFor(int examId, int userId) =>
      recoveries[examId] ?? (savedExamId == examId ? ExamRecoveryState.resumable : ExamRecoveryState.none);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected controller call: ${invocation.memberName}');
}

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  void Function(Route<dynamic>)? onPush;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    onPush?.call(route);
  }
}

// Class #20: 10 AM-noon Los Angeles, PST in November and PDT in July.
Map<String, dynamic> _november(String status) => {
      'exam_id': 31,
      'title': 'November LA exam',
      'duration_minutes': 60,
      'available_from': '2026-11-18T18:00:00.000Z',
      'available_until': '2026-11-18T20:00:00.000+00:00',
      'status': status,
    };
Map<String, dynamic> _july(String status) => {
      'exam_id': 32,
      'title': 'July LA exam',
      'duration_minutes': 60,
      'available_from': '2027-07-15T17:00:00.000+00:00',
      'available_until': '2027-07-15T19:00:00.000Z',
      'status': status,
    };

void main() {
  late ExamSyncService sync;
  late _AssignedAdapter adapter;
  late _Controller controller;
  late _Routes routes;

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://exam.invalid');
    sync = ExamSyncService(
        _UnusedBox<ExamAttempt>(), _UnusedBox<PendingSubmission>());
    // Remove only the secure-storage interceptor; use real Dio JSON decoding.
    sync.dio.interceptors.clear();
    adapter = _AssignedAdapter();
    sync.dio.httpClientAdapter = adapter;
    controller = _Controller();
    routes = _Routes();
  });
  tearDown(() {
    controller.dispose();
    sync.dio.close(force: true);
    dotenv.clean();
  });

  Future<void> show(WidgetTester tester, Object payload,
      {bool rawString = false}) async {
    adapter.payload = payload;
    if (rawString) sync.dio.options.responseType = ResponseType.plain;
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ExamSyncService>.value(value: sync),
        ChangeNotifierProvider<ExamController>.value(value: controller),
      ],
      child: MaterialApp(
          navigatorObservers: [routes],
          home: ExamStart(
            user: User.fromJson(
                {'id': 7, 'first_name': 'Test', 'last_name': 'Student'}),
          )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(adapter.requests.single.path, '/exams/assigned');
  }

  ElevatedButton start(WidgetTester tester) =>
      tester.widget(find.widgetWithText(ElevatedButton, 'Start Exam'));

  final cases = <String, List<Map<String, dynamic>>>{
    'no exams': [],
    'one open exam': [_november('open')],
    'one upcoming exam': [_july('upcoming')],
    'multiple open and upcoming exams': [
      _november('open'),
      {..._november('open'), 'exam_id': 33, 'title': 'Other open'},
      _july('upcoming'),
      {..._july('upcoming'), 'exam_id': 34, 'title': 'Other upcoming'},
    ],
  };

  group('Current service contract', () {
    for (final entry in cases.entries) {
      test('${entry.key}: preserves all fields, statuses and response order',
          () async {
        adapter.payload = entry.value;
        final result = await sync.fetchAssignedExams();
        expect(result, entry.value);
        expect(result.map((e) => e['status']),
            entry.value.map((e) => e['status']));
        expect(adapter.requests, hasLength(1));
      });
    }
  });

  group('Assigned exam selection', () {
    for (final entry in cases.entries) {
      for (final raw in [false, true]) {
        testWidgets('${entry.key}, ${raw ? 'JSON string' : 'decoded array'}',
            (tester) async {
          await show(tester, raw ? jsonEncode(entry.value) : entry.value,
              rawString: raw);
          if (entry.value.isEmpty) {
            expect(
                find.textContaining('You must be scheduled'), findsOneWidget);
          } else {
            for (final exam in entry.value) {
              expect(find.text(exam['title'] as String), findsOneWidget);
              final button = tester.widget<ElevatedButton>(find.descendant(
                  of: find.byKey(ValueKey('exam-${exam['exam_id']}')),
                  matching: find.byType(ElevatedButton)));
              expect(button.onPressed,
                  exam['status'] == 'open' ? isNotNull : isNull);
            }
            expect(find.text("Times shown in your device's local timezone."),
                findsNWidgets(entry.value.length));
          }
          if (entry.value.isEmpty) {
            expect(find.text('Start Exam'), findsNothing);
          }
        });
      }
    }

    for (final fixture in [_november('upcoming'), _july('upcoming')]) {
      testWidgets(
          '${fixture['exam_id']}: explicit offsets render in device local time',
          (tester) async {
        await show(tester, [fixture]);
        // Independent calendar fixtures, rather than parsing the API strings
        // again. Host/device timezone is intentionally retained by this test.
        final november = fixture['exam_id'] == 31;
        final opens = november
            ? DateTime.utc(2026, 11, 18, 18)
            : DateTime.utc(2027, 7, 15, 17);
        final closes = november
            ? DateTime.utc(2026, 11, 18, 20)
            : DateTime.utc(2027, 7, 15, 19);
        final format = DateFormat('MMM d, yyyy   h:mm a');
        expect(find.textContaining('Opens: ${format.format(opens.toLocal())}'),
            findsOneWidget);
        expect(
            find.textContaining('Closes: ${format.format(closes.toLocal())}'),
            findsOneWidget);

        // The same instants expressed with scheduled-zone offsets must render
        // identically; this catches dropping/misreading explicit offsets.
        adapter.payload = [
          {
            ...fixture,
            'available_from': november
                ? '2026-11-18T10:00:00-08:00'
                : '2027-07-15T10:00:00-07:00',
            'available_until': november
                ? '2026-11-18T12:00:00-08:00'
                : '2027-07-15T12:00:00-07:00',
          }
        ];
        await tester.pumpWidget(const SizedBox.shrink());
        adapter.requests.clear();
        await show(tester, adapter.payload);
        expect(find.textContaining('Opens: ${format.format(opens.toLocal())}'),
            findsOneWidget);
        expect(
            find.textContaining('Closes: ${format.format(closes.toLocal())}'),
            findsOneWidget);
      });
    }

    for (final payload in [
      <Map<String, dynamic>>[],
      [_july('upcoming')]
    ]) {
      testWidgets(
          'saved session resumes before assignment refetch (${payload.isEmpty ? 'empty' : 'upcoming'})',
          (tester) async {
        controller.savedExamId = 99;
        controller.remainingSeconds = 1200;
        await show(tester, payload);
        final context = tester.element(find.byType(ExamStart));
        // Run the real button callback without building the destination page;
        // ExamPage owns timer behavior, which is outside this regression scope.
        await tester.runAsync(() async {
          tester
              .widget<ElevatedButton>(find.byKey(const ValueKey('resume-exam')))
              .onPressed!();
          await Future<void>.delayed(Duration.zero);
        });
        expect(controller.restores, 1);
        expect(controller.starts, 0);
        expect(adapter.requests, hasLength(1));
        expect(routes.pushed, hasLength(2));
        final page = (routes.pushed.last as MaterialPageRoute).builder(context)
            as ExamPage;
        expect(page.examId, 99);
        expect(page.userId, 7);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  testWidgets(
      'second open exam uses its own ID and preserves server rejection handling',
      (tester) async {
    await show(tester, [_november('open'), _july('open')]);
    final button = find.descendant(
        of: find.byKey(const ValueKey('exam-32')),
        matching: find.byType(ElevatedButton));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(controller.startedIds, [32]);
    expect(controller.restores, 1);
    expect(adapter.requests, hasLength(1));
    expect(find.textContaining('server session could not be safely verified'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
  });

  testWidgets('retrieval failure shows retry and recovers', (tester) async {
    adapter.statusCode = 500;
    await show(tester, []);
    expect(
        find.textContaining('Unable to load assigned exams'), findsOneWidget);
    expect(find.text('Start Exam'), findsNothing);
    adapter.statusCode = 200;
    adapter.payload = [_november('open')];
    await tester.tap(find.text('Refresh exams'));
    await tester.pumpAndSettle();
    expect(find.text('November LA exam'), findsOneWidget);
    expect(find.textContaining('Unable to load assigned exams'), findsNothing);
    expect(adapter.requests, hasLength(2));
  });

  testWidgets('refresh on app resume updates availability without polling',
      (tester) async {
    await show(tester, [_july('upcoming')]);
    adapter.payload = [_july('open')];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(start(tester).onPressed, isNotNull);
    expect(adapter.requests, hasLength(2));
    await tester.pump(const Duration(minutes: 5));
    expect(adapter.requests, hasLength(2));
  });

  testWidgets('selected exam navigation carries its ID and refreshes on return',
      (tester) async {
    controller.questions = [
      {'id': 1}
    ];
    await show(tester, [_november('open'), _july('open')]);
    final context = tester.element(find.byType(ExamStart));
    ExamPage? destination;
    routes.onPush = (route) {
      destination = (route as MaterialPageRoute).builder(context) as ExamPage;
      adapter.payload = [_november('upcoming')];
      // Return before rendering the destination: no exam timers are involved.
      scheduleMicrotask(() => Navigator.of(context).removeRoute(route));
    };
    final button = tester.widget<ElevatedButton>(find.descendant(
        of: find.byKey(const ValueKey('exam-32')),
        matching: find.byType(ElevatedButton)));
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(controller.startedIds, [32]);
    expect(destination?.examId, 32);
    expect(destination?.sessionData?['examTitle'], 'July LA exam');
    expect(adapter.requests, hasLength(2));
    expect(find.text('July LA exam'), findsNothing);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(start(tester).onPressed, isNull);
  });

  testWidgets('loading has no start action and keeps saved recovery accessible',
      (tester) async {
    // Render once, then hold an explicit refresh request in flight.
    controller.savedExamId = 99;
    await show(tester, [_november('open')]);
    adapter.pending = Completer<void>();
    await tester.tap(find.text('Refresh exams'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Start Exam'), findsNothing);
    expect(
        tester
            .widget<ElevatedButton>(find.byKey(const ValueKey('resume-exam')))
            .onPressed,
        isNotNull);
    adapter.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(start(tester).onPressed, isNotNull);
  });

  testWidgets('unresolved saved session cannot start from selection', (tester) async {
    controller.recoveries[31] = ExamRecoveryState.unresolved;
    await show(tester, [_november('open')]);
    await tester.ensureVisible(find.text('Start Exam'));
    await tester.tap(find.text('Start Exam'));
    await tester.pumpAndSettle();
    expect(controller.restores, 0);
    // Entry delegates to the controller's guarded recovery/start operation.
    expect(controller.starts, 1);
    expect(adapter.requests, hasLength(1));
    expect(find.textContaining('saved exam session needs recovery'), findsOneWidget);
  });

  group('Availability presentation', () {
    testWidgets('upcoming status is exposed to the student', (tester) async {
      await show(tester, [_july('upcoming')]);
      expect(find.textContaining('Upcoming'), findsOneWidget);
    });

    testWidgets('upcoming exam cannot start a new session', (tester) async {
      await show(tester, [_july('upcoming')]);
      expect(start(tester).onPressed, isNull);
    });

    testWidgets('all returned exams are available for presentation',
        (tester) async {
      await show(tester, [_november('open'), _july('upcoming')]);
      expect(find.textContaining('November LA exam'), findsOneWidget);
      expect(find.textContaining('July LA exam'), findsOneWidget);
    });
  });
}
