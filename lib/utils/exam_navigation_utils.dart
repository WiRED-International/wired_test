import 'package:flutter/material.dart';
import '../../pages/exam/review_answers_page.dart';
import '../../state/exam_controller.dart';

class ExamNavigationUtils {
  // A review route remains one footer action until it returns. Identity avoids
  // sharing the guard between unrelated controller instances.
  static final Set<ExamController> _pendingFooterActions = Set.identity();

  static Future<void> returnHomeAfterSubmission({
    required BuildContext context,
    required ExamController controller,
    int? generation,
  }) async {
    final ownerGeneration = generation ?? controller.persistenceGeneration;
    if (ownerGeneration != controller.persistenceGeneration) return;
    await controller.clearExamPersistence(generation: ownerGeneration);
    if (!context.mounted || controller.active != null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static Future<void> handleFooterTap({
    required BuildContext context,
    required ExamController controller,
    required PageController pageController,
    required int currentIndex,
    required int totalQuestions,
    required List<Map<String, dynamic>> questions,
    required bool cameBackFromReview,
    int? generation,

    /// Callbacks to update state inside ExamPage:
    required Function(int newIndex) updateIndex,
    required Function(bool value) updateCameBackFromReview,
    required Function() refreshScrollHintForCurrent,
  }) async {
    final ownerGeneration = generation ?? controller.persistenceGeneration;
    if (!context.mounted ||
        controller.persistenceTransitioning ||
        ownerGeneration != controller.persistenceGeneration ||
        !_pendingFooterActions.add(controller)) {
      return;
    }
    try {
      final nextIndex = currentIndex + 1;

      // 🟣 RE-ENTERING REVIEW FLOW
      if (cameBackFromReview) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ReviewAnswersPage(questions: questions)),
        );

        if (!context.mounted ||
            ownerGeneration != controller.persistenceGeneration) return;

        // User tapped a specific question card in Review → jump there
        if (result is int && result >= 0 && result < totalQuestions) {
          updateIndex(result);
          updateCameBackFromReview(true);
          refreshScrollHintForCurrent();
          pageController.jumpToPage(result);
          return;
        }

        // User just backed out of review without jumping anywhere
        if (result == 'back_to_questions') {
          // Stay on currentIndex; just refresh UI state
          updateCameBackFromReview(true);
          refreshScrollHintForCurrent();
          return;
        }
        // Dismissal (including success popUntil) ends this action. It must not
        // fall through into the last-question branch and push another review.
        return;
      }

      // Save progress toward the *next* question before moving
      controller.saveProgress(nextIndex, generation: ownerGeneration);

      // 🟢 NEXT QUESTION
      if (currentIndex < totalQuestions - 1) {
        updateIndex(nextIndex);
        await pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        if (!context.mounted ||
            ownerGeneration != controller.persistenceGeneration) return;
        updateIndex(nextIndex);
        updateCameBackFromReview(false);
        refreshScrollHintForCurrent();
        return;
      }

      // 🟡 LAST QUESTION → OPEN REVIEW
      if (currentIndex == totalQuestions - 1) {
        // First time going into review from last question
        updateCameBackFromReview(false);

        final result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ReviewAnswersPage(questions: questions)),
        );

        if (!context.mounted ||
            ownerGeneration != controller.persistenceGeneration) return;

        if (result == 'back_to_questions') {
          // User came back without submitting
          updateCameBackFromReview(true);
          refreshScrollHintForCurrent();
          return;
        }

        if (result is int && result < totalQuestions) {
          // User picked a specific question from review
          updateIndex(result);
          updateCameBackFromReview(true);

          await pageController.animateToPage(
            result,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
          if (!context.mounted ||
              ownerGeneration != controller.persistenceGeneration) return;
          refreshScrollHintForCurrent();
          return;
        }
      }
    } finally {
      _pendingFooterActions.remove(controller);
    }
  }
}
