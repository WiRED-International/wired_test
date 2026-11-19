import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/pages/exam/review_answers_page.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';
import 'package:wired_test/widgets/exam/footer_buttons.dart';
import 'package:wired_test/utils/exam_navigation_utils.dart';

// Reproduction boundary: production NetworkUtils performs non-injectable DNS.
// Submit through the real service with fake HTTP, then drive the success tail
// from ReviewAnswersPage through its production cleanup/navigation helper.
// The actual footer/helper, review UI, controller, and Hive storage are used.
// This deliberately does not claim to exercise _confirmSubmission/_handleSubmit.
class _Http extends Fake implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (options.method != 'PUT' ||
        options.path != '/exam-sessions/122/submit') {
      throw StateError(
          'Unexpected request; no exam may start: ${options.method} ${options.path}');
    }
    return ResponseBody.fromString(
        '{"message":"Exam submitted successfully","resolved_session_id":122}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

class _GatedBox extends Fake implements Box<dynamic> {
  _GatedBox(this.delegate);
  final Box<dynamic> delegate;
  Completer<void>? deleteGate;
  final deleteStarted = Completer<void>();
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) => delegate.put(key, value);
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) =>
      delegate.putAll(entries);
  @override
  Future<void> delete(dynamic key) async {
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await deleteGate?.future;
    await delegate.delete(key);
  }
}

class _Routes extends NavigatorObserver {
  int reviewPushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute && previousRoute != null) {
      // Home is the only route with a name; both remaining route types are
      // counted via the explicit review type when their builders are inspected.
      final context = navigator!.context;
      if (route.builder(context) is ReviewAnswersPage) reviewPushes++;
    }
  }
}

class _Questions extends StatefulWidget {
  const _Questions({required this.controller});
  final ExamController controller;
  @override
  State<_Questions> createState() => _QuestionsState();
}

class _QuestionsState extends State<_Questions> {
  final pages = PageController();
  late final int generation = widget.controller.persistenceGeneration;
  bool cameBack = false;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('exam to test')),
        body: const Text('Completed question 23 of 23'),
        bottomNavigationBar: FooterButtons(
          parentContext: context,
          controller: widget.controller,
          persistenceGeneration: generation,
          currentIndex: 22,
          totalQuestions: 23,
          cameBackFromReview: cameBack,
          examExpired: false,
          pageController: pages,
          updateIndex: (_) {},
          updateCameBackFromReview: (value) => setState(() => cameBack = value),
          refreshScrollHintForCurrent: () {},
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Box<ExamAttempt> attempts;
  late Box<PendingSubmission> retries;
  late Box<dynamic> examBox;
  late _GatedBox gated;
  late ExamController controller;
  late ExamSyncService sync;
  late _Http http;
  late _Routes routes;
  Future<void>? cleanup;
  final navigator = GlobalKey<NavigatorState>();

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
    Hive.registerAdapter(PendingSubmissionAdapter());
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('exam_navigation_repro_');
    Hive.init(temp.path);
    attempts = await Hive.openBox<ExamAttempt>('attempts');
    retries = await Hive.openBox<PendingSubmission>('retries');
    examBox = await Hive.openBox('exam');
    final time = DateTime.utc(2026, 11, 16, 9, 27, 19);
    await attempts.put(
        '122',
        ExamAttempt(
          attemptId: '122',
          examId: 26,
          userId: 1,
          startedAt: time,
          durationSeconds: 2700,
          answers: List.generate(
              23,
              (i) => AnswerRecord(
                  questionId: i + 1,
                  selectedOptionId: 'a',
                  selectedOptionIds: ['a'],
                  updatedAt: time)),
        ));
    await examBox.putAll({
      'exam_start_time': time.toIso8601String(),
      'exam_duration': 45,
      'exam_id': 26,
      'user_id': 1,
      'attempt_id': '122',
      'session_id': 122,
      'current_index': 22,
      'remaining_seconds': 2400,
      'is_paused': true,
      'cached_questions': List.generate(
          23,
          (i) => {
                'id': i + 1,
                'question_text': 'Exam A question ${i + 1}',
                'options': {'a': 'Selection A', 'b': 'Selection B'},
              }),
    });
    dotenv.loadFromString(envString: 'API_BASE_URL=https://exam.invalid');
    sync = ExamSyncService(attempts, retries);
    sync.dio.interceptors.clear();
    http = _Http();
    sync.dio.httpClientAdapter = http;
    gated = _GatedBox(examBox);
    controller = ExamController(attempts, sync, gated);
    await controller.restoreExamIfExists();
    routes = _Routes();
    cleanup = null;
  });
  tearDown(() async {
    if (gated.deleteGate != null && !gated.deleteGate!.isCompleted) {
      gated.deleteGate!.complete();
    }
    if (cleanup != null) await cleanup;
    controller.dispose();
    sync.dio.close(force: true);
    await Hive.close();
    // Only the unique test directory created above is removed.
    await temp.delete(recursive: true);
    dotenv.clean();
  });

  Future<void> showQuestions(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<ExamController>.value(
      value: controller,
      child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routes],
          home: const Scaffold(body: Text('Intended Home'))),
    ));
    navigator.currentState!.push(
        MaterialPageRoute(builder: (_) => _Questions(controller: controller)));
    await tester.pumpAndSettle();
  }

  Future<void> review(WidgetTester tester, {bool reenter = false}) async {
    await tester.runAsync(() async {
      tester
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Review Answers'))
          .onPressed!();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    if (reenter) {
      await tester.tap(find.text('Back to Questions'));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(tester.state<_QuestionsState>(find.byType(_Questions)).cameBack,
          isTrue);
      await tester.runAsync(() async {
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Review Answers'))
            .onPressed!();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
    }
    expect(find.byType(ReviewAnswersPage), findsOneWidget);
  }

  Future<void> acceptAndReturn(WidgetTester tester) async {
    final payload = await controller.buildSubmissionPayload();
    await tester.runAsync(() async {
      expect(await sync.submitExam(payload!), isTrue);
    });
    expect(attempts.get('122')!.submitted, isTrue);
    expect(http.requests, hasLength(1));
    expect(http.requests.single.data['exam_id'], 26);
    expect(http.requests.single.data['answers'], hasLength(23));
    expect(retries.isEmpty, isTrue);
    final reviewContext = tester.element(find.byType(ReviewAnswersPage));
    // Invoke the same production completion helper as ReviewAnswersPage.
    // Retain the future so tests can inspect a blocked cleanup before release.
    await tester.runAsync(() async {
      cleanup = ExamNavigationUtils.returnHomeAfterSubmission(
          context: reviewContext, controller: controller);
      if (gated.deleteGate == null) {
        await cleanup;
      } else {
        await gated.deleteStarted.future;
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('first review: accepted Exam A returns home without another exam',
      (tester) async {
    await showQuestions(tester);
    await review(tester);
    await acceptAndReturn(tester);
    expect(find.text('Intended Home'), findsOneWidget);
    expect(find.byType(ReviewAnswersPage), findsNothing);
    expect(routes.reviewPushes, 1);
    expect(http.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.runAsync(() async {
      await cleanup;
    });
    expect(controller.active, isNull);
  });

  testWidgets(
      'REGRESSION: pending re-entered review must not reopen after accepted submission',
      (tester) async {
    await showQuestions(tester);
    await review(tester, reenter: true);
    expect(routes.reviewPushes, 2);
    await acceptAndReturn(tester);
    // Submission must end the pending review action, without a third push.
    expect(routes.reviewPushes, 2,
        reason: 'No third review may be pushed after submission');
    expect(find.text('Intended Home'), findsOneWidget);
    expect(find.byType(ReviewAnswersPage), findsNothing);
  });

  testWidgets('completed Exam A leaves no stale review or active answers',
      (tester) async {
    await showQuestions(tester);
    await review(tester, reenter: true);
    await acceptAndReturn(tester);
    expect(routes.reviewPushes, 2);
    expect(find.byType(ReviewAnswersPage), findsNothing);
    expect(find.text('Intended Home'), findsOneWidget);
    expect(controller.active, isNull);
    expect(examBox.get('exam_id'), isNull);
    expect(examBox.get('cached_questions'), isNull);
    expect(http.requests, hasLength(1));
    expect(http.requests.single.path, '/exam-sessions/122/submit');
  });

  testWidgets(
      'returning to questions allows intentionally reopening review repeatedly',
      (tester) async {
    await showQuestions(tester);
    await review(tester, reenter: true);
    expect(routes.reviewPushes, 2);
    await tester.tap(find.text('Back to Questions'));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await review(tester);
    expect(routes.reviewPushes, 3);
    expect(controller.active?.examId, 26);
    expect(controller.active!.answers, hasLength(23));
    expect(http.requests, isEmpty);
  });

  testWidgets(
      'REGRESSION: repeated footer callbacks must create only one review route',
      (tester) async {
    await showQuestions(tester);
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Review Answers'));
    // Two callbacks before the next frame models rapid/reentrant activation.
    await tester.runAsync(() async {
      button.onPressed!();
      button.onPressed!();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(routes.reviewPushes, 1,
        reason: 'Footer navigation must be single-flight');
  });

  testWidgets(
      'REGRESSION: success must not return home before saved-session cleanup finishes',
      (tester) async {
    await showQuestions(tester);
    await review(tester);
    await tester.runAsync(() async {
      gated.deleteGate = Completer<void>();
    });
    await acceptAndReturn(tester);
    expect(gated.deleteStarted.isCompleted, isTrue);
    // Demonstrate this is genuinely incomplete persisted cleanup.
    expect(examBox.get('exam_id'), 26);
    expect(controller.active?.attemptId, '122');
    final returnedHome = find.text('Intended Home').evaluate().isNotEmpty;
    await tester.runAsync(() async {
      gated.deleteGate!.complete();
      await cleanup;
    });
    expect(returnedHome, isFalse,
        reason:
            'Navigation must await cleanup instead of treating the exam as cleared');
    await tester.pumpAndSettle();
    expect(find.text('Intended Home'), findsOneWidget);
    expect(find.byType(ReviewAnswersPage), findsNothing);
    expect(controller.active, isNull);
    expect(examBox.get('exam_id'), isNull);
  });

  test(
      'control: awaiting cleanup finishes before the completed attempt is cleared',
      () async {
    final payload = await controller.buildSubmissionPayload();
    expect(await sync.submitExam(payload!), isTrue);
    gated.deleteGate = Completer<void>();
    var finished = false;
    cleanup = controller.clearExamPersistence().then((_) {
      finished = true;
    });
    await gated.deleteStarted.future;
    expect(finished, isFalse);
    expect(examBox.get('exam_id'), 26);
    expect(controller.active, isNotNull);
    gated.deleteGate!.complete();
    await cleanup;
    expect(finished, isTrue);
    expect(controller.active, isNull);
    expect(examBox.get('exam_id'), isNull);
    expect(examBox.get('cached_questions'), isNull);
    expect(attempts.get('122'), isNull);
  });
}
