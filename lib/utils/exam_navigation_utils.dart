import 'package:flutter/material.dart';
import '../../pages/exam/review_answers_page.dart';
import '../../state/exam_controller.dart';

class ExamNavigationUtils {
  static Future<void> handleFooterTap({
    required BuildContext context,
    required ExamController controller,
    required PageController pageController,
    required int currentIndex,
    required int totalQuestions,
    required List<Map<String, dynamic>> questions,
    required bool cameBackFromReview,
    required bool readyToSubmit,

    /// Callbacks to update state inside ExamPage:
    required Function(int newIndex) updateIndex,
    required Function(bool value) updateCameBackFromReview,
    required Function(bool value) updateReadyToSubmit,
    required Function() refreshScrollHintForCurrent,
  }) async {
    final nextIndex = currentIndex + 1;

    // 🟣 RE-ENTERING REVIEW FLOW
    if (cameBackFromReview && !readyToSubmit) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewAnswersPage(questions: questions)),
      );

      if (result == 'submitted') {
        updateReadyToSubmit(true);
        updateCameBackFromReview(false);
        return;
      }

      // User tapped a specific question card in Review → jump there
      if (result is int && result >= 0 && result < totalQuestions) {
        updateIndex(result);
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
        refreshScrollHintForCurrent();
        pageController.jumpToPage(result);
        return;
      }

      // User just backed out of review without jumping anywhere
      if (result == 'back_to_questions') {
        // Stay on currentIndex; just refresh UI state
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
        refreshScrollHintForCurrent();
        return;
      }
    }

    // Save progress toward the *next* question before moving
    controller.saveProgress(nextIndex);

    // 🟢 NEXT QUESTION
    if (currentIndex < totalQuestions - 1) {
      updateIndex(nextIndex);
      await pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      updateIndex(nextIndex);
      updateCameBackFromReview(false);
      updateReadyToSubmit(false);
      refreshScrollHintForCurrent();
      return;
    }

    // 🟡 LAST QUESTION → OPEN REVIEW
    if (currentIndex == totalQuestions - 1 && !readyToSubmit) {
      // First time going into review from last question
      updateCameBackFromReview(false);

      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewAnswersPage(questions: questions)),
      );

      if (result == 'back_to_questions') {
        // User came back without submitting
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
        refreshScrollHintForCurrent();
        return;
      }

      if (result == 'submitted') {
        // User submitted from review
        updateReadyToSubmit(true);
        updateCameBackFromReview(false);
        return;
      }

      if (result is int && result < totalQuestions) {
        // User picked a specific question from review
        updateIndex(result);
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);

        await pageController.animateToPage(
          result,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        refreshScrollHintForCurrent();
        return;
      }
    }

    // 🔵 FULL READY → user has reviewed & is allowed to submit
    if (readyToSubmit) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewAnswersPage(questions: questions),
        ),
      );

      if (result == 'submitted') {
        // Already handled submit → go home
        Future.delayed(const Duration(milliseconds: 100), () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        });
      } else if (result == 'back_to_questions') {
        // User wants to tweak answers again from where they were
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
        refreshScrollHintForCurrent();
      } else if (result is int && result < totalQuestions) {
        // User chose a specific question to return to
        updateIndex(result);
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
        pageController.jumpToPage(result);
      }
    }
  }
}