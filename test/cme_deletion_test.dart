import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/submit_credits.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/services/pending_quiz_score_repository.dart';

class _Auth extends AuthProvider {
  String token = 'A';
  @override
  bool get isLoggedIn => true;
  @override
  String get authToken => token;
  @override
  String getUserIdFromToken() => '7';
  void switchAccount() {
    token = token == 'A' ? 'B' : 'A';
    notifyListeners();
  }
}

void main() {
  late _Auth auth;
  late PendingQuizScoreRepository repository;
  late String? raw;
  Completer<void>? gate;
  late int reads;
  late int mutations;
  late bool fail;

  setUp(() {
    auth = _Auth();
    raw = jsonEncode({
      '1234': {'module_name': 'A lesson', 'score': 95, 'date_saved': 'old'},
      '5678': {'module_name': 'Z lesson', 'score': 88},
    });
    gate = null;
    reads = 0;
    mutations = 0;
    fail = false;
  });
  tearDown(() => auth.dispose());

  Future<void> mount(WidgetTester tester) async {
    repository = PendingQuizScoreRepository(
      read: () async {
        reads++;
        final pending = gate;
        if (pending != null) await pending.future;
        return raw;
      },
      write: (value) async {
        if (fail) throw StateError('storage unavailable');
        mutations++;
        raw = value;
      },
      delete: () async {
        if (fail) throw StateError('storage unavailable');
        mutations++;
        raw = null;
      },
    );
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<PendingQuizScoreRepository>.value(value: repository),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.7)),
          child: child!,
        ),
        home: SubmitCredits(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('A lesson'), findsOneWidget);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Delete').first);
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Module'), findsOneWidget);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Yes, delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Module'), findsNothing);
  }

  testWidgets('cancel leaves the score untouched', (tester) async {
    await mount(tester);
    final before = raw;
    await open(tester);
    await tester.tap(find.text('Do not delete'));
    await tester.pumpAndSettle();
    expect(raw, before);
    expect(mutations, 0);
    expect(find.text('A lesson'), findsOneWidget);
  });

  testWidgets('successful deletion refreshes and preserves unrelated scores',
      (tester) async {
    await mount(tester);
    final other = (jsonDecode(raw!) as Map)['5678'];
    await open(tester);
    await confirm(tester);
    expect(find.text('A lesson'), findsNothing);
    expect(find.text('Z lesson'), findsOneWidget);
    expect(jsonDecode(raw!), {'5678': other});
  });

  testWidgets('deleting the last score shows the empty state', (tester) async {
    final scores = jsonDecode(raw!) as Map;
    scores.remove('5678');
    raw = jsonEncode(scores);
    await mount(tester);
    await open(tester);
    await confirm(tester);
    expect(raw, isNull);
    expect(find.textContaining('No saved scores yet.'), findsOneWidget);
  });

  testWidgets('delayed deletion refreshes after the dialog is dismissed',
      (tester) async {
    await mount(tester);
    await open(tester);
    gate = Completer<void>();
    await confirm(tester);
    expect(mutations, 0);
    gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('A lesson'), findsNothing);
    expect(find.text('Z lesson'), findsOneWidget);
  });

  for (final last in [false, true]) {
    testWidgets('storage ${last ? 'delete' : 'write'} failure shows feedback',
        (tester) async {
      if (last) {
        final scores = jsonDecode(raw!) as Map;
        scores.remove('5678');
        raw = jsonEncode(scores);
      }
      await mount(tester);
      final before = raw;
      await open(tester);
      fail = true;
      gate = Completer<void>();
      await confirm(tester);
      gate!.complete();
      await tester.pumpAndSettle();
      expect(raw, before);
      expect(find.text('A lesson'), findsOneWidget);
      expect(find.textContaining('could not be removed'), findsOneWidget);
    });
  }

  testWidgets('a newer retake is preserved and refreshed with feedback',
      (tester) async {
    await mount(tester);
    await open(tester);
    // Save through the real repository while the old snapshot is displayed.
    await repository.save(
        moduleId: '1234', moduleName: 'New retake', score: 80);
    final before = raw;
    await confirm(tester);
    expect(raw, before);
    expect(find.text('New retake'), findsOneWidget);
    expect(find.text('80.00'), findsOneWidget);
    expect(find.textContaining('newer saved score'), findsOneWidget);
  });

  for (final failure in [false, true]) {
    testWidgets(
        'account change suppresses stale deletion UI (failure=$failure)',
        (tester) async {
      await mount(tester);
      await open(tester);
      gate = Completer<void>();
      fail = failure;
      await confirm(tester);
      final beforeCompletion = reads;
      auth.switchAccount();
      auth.switchAccount(); // Reusing A must not restore operation ownership.
      gate!.complete();
      await tester.pumpAndSettle();
      expect(reads, beforeCompletion); // No stale list refresh.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('A lesson'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account change before confirmation prevents deletion',
      (tester) async {
    await mount(tester);
    await open(tester);
    final before = raw;
    auth.switchAccount();
    await confirm(tester);
    expect(raw, before);
    expect(mutations, 0);
  });

  testWidgets('page disposal during deletion causes no exceptions',
      (tester) async {
    await mount(tester);
    await open(tester);
    gate = Completer<void>();
    await confirm(tester);
    final beforeCompletion = reads;
    await tester.pumpWidget(const SizedBox.shrink());
    gate!.complete();
    await tester.pumpAndSettle();
    expect(reads, beforeCompletion);
    expect(mutations, 1);
    expect(tester.takeException(), isNull);
  });
}
