import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/models/cme_credit_totals.dart';
import 'package:wired_test/models/user.dart';
import 'package:wired_test/pages/cme/cme_tracker.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';

class _Scores extends QuizScoreProvider {
  @override
  Future<void> fetchQuizScores() async {}
}

Map<String, dynamic> profile({int earned = 35, String status = 'available'}) =>
    {
      'id': 7,
      'first_name': 'Test',
      'quizScores': <dynamic>[],
      'cmeCredits': {
        'status': status,
        'annualRequirement': 75,
        'currentYear': {'year': 2031, 'earnedCredits': earned},
        'previousYear': {'year': 2030, 'earnedCredits': 60},
      },
    };

void main() {
  test('profile preserves fields and parses backend years and balances', () {
    final user = User.fromJson(profile());
    expect(user.firstName, 'Test');
    expect(user.id, 7);
    expect(user.creditsEarned, 35);
    expect(user.cmeCredits.annualRequirement, 75);
    expect(user.cmeCredits.currentYear.year, 2031);
    expect(user.cmeCredits.previousYear.year, 2030);
    expect(user.cmeCredits.previousYear.earnedCredits, 60);
    expect(
        CmeCreditTotals.fromJson(user.toJson()['cmeCredits'])
            .currentYear
            .earnedCredits,
        35);
  });

  test('missing, unavailable and malformed totals never become zero', () {
    expect(User.fromJson({'quizScores': []}).creditsEarned, isNull);
    expect(User.fromJson(profile(status: 'unavailable')).creditsEarned, isNull);
    final data = profile();
    (data['cmeCredits'] as Map)['currentYear'] = {
      'year': 2031,
      'earnedCredits': -1,
    };
    expect(User.fromJson(data).creditsEarned, isNull);
  });

  for (final size in [const Size(400, 900), const Size(1200, 800)]) {
    for (final earned in [0, 35]) {
      testWidgets('ledger $earned with no history at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scores = _Scores();
        await tester.pumpWidget(ChangeNotifierProvider<QuizScoreProvider>.value(
          value: scores,
          child: MaterialApp(
              // Ahem test-font labels overflow the existing shared navigation at
              // default scale; exercise the CME layouts without changing that UI.
              builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(0.9)),
                    child: child!,
                  ),
              home: CMETracker(
                loadUser: () async => User.fromJson(profile(earned: earned)),
              )),
        ));
        await tester.pumpAndSettle();
        expect(find.text('$earned credits earned'), findsOneWidget);
        expect(find.text('Annual requirement: 75 credits'), findsOneWidget);
        expect(find.text('2031 Progress'), findsOneWidget);
        expect(find.text('2030: 60 credits earned'), findsNothing);
        scores.updateScore({
          'module_id': 1,
          'module_name': 'Retake',
          'credit_type': 'cme',
          'score': 100,
          'date_taken': '2031-01-01',
        });
        await tester.pumpAndSettle();
        expect(find.text('$earned credits earned'), findsOneWidget);
        expect(find.text('5 credits'), findsNothing);
        expect(find.text('Recent Quiz Submissions'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        scores.dispose();
      });
    }

    testWidgets('unavailable totals at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scores = _Scores();
      await tester.pumpWidget(ChangeNotifierProvider<QuizScoreProvider>.value(
        value: scores,
        child: MaterialApp(
            // Ahem test-font labels overflow the existing shared navigation at
            // default scale; exercise the CME layouts without changing that UI.
            builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(0.9)),
                  child: child!,
                ),
            home: CMETracker(
              loadUser: () async =>
                  User.fromJson(profile(status: 'unavailable')),
            )),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Credits unavailable'), findsOneWidget);
      expect(find.text('2030: Credits unavailable'), findsNothing);
      expect(find.text('0 credits earned'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pumpWidget(const SizedBox());
      scores.dispose();
    });
  }
}
