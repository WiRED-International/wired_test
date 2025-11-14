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

    // 🟣 Re-entering Review
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

      if (result is int && result >= 0 && result < totalQuestions) {
        updateIndex(result);
        updateCameBackFromReview(true);
        refreshScrollHintForCurrent();
        pageController.jumpToPage(result);
        return;
      }

      if (result == 'back_to_questions') {
        refreshScrollHintForCurrent();
        return;
      }
    }

    controller.saveProgress(nextIndex);

    // 🟢 NEXT QUESTION
    if (currentIndex < totalQuestions - 1) {
      updateIndex(nextIndex);
      pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      return;
    }

    // 🟡 LAST QUESTION → ReviewAnswersPage
    if (currentIndex == totalQuestions - 1 && !readyToSubmit) {
      updateCameBackFromReview(false);

      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewAnswersPage(questions: questions)),
      );

      if (result == 'back_to_questions') {
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
        return;
      }

      if (result == 'submitted') {
        updateReadyToSubmit(true);
        updateCameBackFromReview(false);
        return;
      }

      if (result is int && result < totalQuestions) {
        updateIndex(result);
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);

        await pageController.animateToPage(
          result,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );

        return;
      }
    }

    // 🔵 FULL READY → final confirmation
    if (readyToSubmit) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewAnswersPage(questions: questions)),
      );

      if (result == 'submitted') {
        Future.delayed(const Duration(milliseconds: 100), () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        });
      } else if (result == 'back_to_questions') {
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
      } else if (result is int && result < totalQuestions) {
        updateIndex(result);
        updateCameBackFromReview(true);
        updateReadyToSubmit(false);
        pageController.jumpToPage(result);
      }
    }
  }
}