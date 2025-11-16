import 'package:flutter/material.dart';
import '../../utils/screen_utils.dart';
import '../../utils/exam_navigation_utils.dart';
import '../../state/exam_controller.dart';

class FooterButtons extends StatelessWidget {
  final BuildContext parentContext;
  final ExamController controller;

  final int currentIndex;
  final int totalQuestions;
  final bool cameBackFromReview;
  final bool readyToSubmit;
  final bool examExpired;

  final PageController pageController;

  // callbacks to update ExamPage state
  final Function(int newIndex) updateIndex;
  final Function(bool value) updateCameBackFromReview;
  final Function(bool value) updateReadyToSubmit;
  final Function() refreshScrollHintForCurrent;

  const FooterButtons({
    super.key,
    required this.parentContext,
    required this.controller,
    required this.currentIndex,
    required this.totalQuestions,
    required this.cameBackFromReview,
    required this.readyToSubmit,
    required this.pageController,
    required this.updateIndex,
    required this.updateCameBackFromReview,
    required this.updateReadyToSubmit,
    required this.refreshScrollHintForCurrent,
    required this.examExpired,
  });

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortest >= 600;

    final double vPad = isTablet ? shortest * 0.025 : shortest * 0.03;
    final double hPad = shortest * 0.04;
    final double fontSize = ScreenUtils.scaleFont(context, 16);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // PREVIOUS
          Expanded(
            child: OutlinedButton(
              onPressed: examExpired
                  ? null
                  : (currentIndex > 0
                  ? () {
                pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
                updateIndex(currentIndex - 1);
              }
                  : null),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.symmetric(vertical: vPad * 0.7),
              ),
              child: Text(
                "Previous",
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          SizedBox(width: hPad * 0.5),

          // NEXT / REVIEW / SUBMIT
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.symmetric(vertical: vPad * 0.7),
              ),
              onPressed: examExpired
                  ? () {
                // user is expired → force “Review Answers”
                ExamNavigationUtils.handleFooterTap(
                  context: parentContext,
                  controller: controller,
                  pageController: pageController,
                  currentIndex: currentIndex,
                  totalQuestions: totalQuestions,
                  questions: controller.getCachedQuestions() ?? [],
                  cameBackFromReview: cameBackFromReview,
                  readyToSubmit: readyToSubmit,
                  updateIndex: updateIndex,
                  updateCameBackFromReview: updateCameBackFromReview,
                  updateReadyToSubmit: updateReadyToSubmit,
                  refreshScrollHintForCurrent: refreshScrollHintForCurrent,
                );
              }
                  : () {
                // normal behavior (not expired)
                ExamNavigationUtils.handleFooterTap(
                  context: parentContext,
                  controller: controller,
                  pageController: pageController,
                  currentIndex: currentIndex,
                  totalQuestions: totalQuestions,
                  questions: controller.getCachedQuestions() ?? [],
                  cameBackFromReview: cameBackFromReview,
                  readyToSubmit: readyToSubmit,
                  updateIndex: updateIndex,
                  updateCameBackFromReview: updateCameBackFromReview,
                  updateReadyToSubmit: updateReadyToSubmit,
                  refreshScrollHintForCurrent: refreshScrollHintForCurrent,
                );
              },
              child: Text(
                examExpired
                    ? 'Review Answers' // always
                    : cameBackFromReview
                      ? 'Review Answers'
                      : currentIndex < totalQuestions - 1
                        ? 'Next Question'
                        : readyToSubmit
                          ? 'Submit Exam'
                          : 'Review Answers',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
