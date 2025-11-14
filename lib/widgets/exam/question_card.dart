import 'package:flutter/material.dart';
import '../../state/exam_controller.dart';
import '../../models/exam_models.dart';
import '../../utils/screen_utils.dart';

class QuestionCard extends StatefulWidget {
  final BuildContext parentContext;
  final ExamController controller;
  final Map<String, dynamic> question;
  final int index;
  final int totalQuestions;

  // scroll maps come directly from ExamPage
  final Map<int, bool> isListScrollable;
  final Map<int, bool> listAtBottom;
  final Map<int, ScrollController> scrollControllers;

  const QuestionCard({
    super.key,
    required this.parentContext,
    required this.controller,
    required this.question,
    required this.index,
    required this.totalQuestions,
    required this.isListScrollable,
    required this.listAtBottom,
    required this.scrollControllers,
  });

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final controller = widget.controller;
    final index = widget.index;

    final questionText = q['question_text'] ?? q['text'] ?? 'No question text';
    final optionsData = q['options'];
    final isMultiple = q['question_type'] == 'multiple';

    List<dynamic> options = [];

    if (optionsData is Map<String, dynamic>) {
      options = optionsData.entries
          .map((e) => {'key': e.key, 'value': e.value})
          .toList();
    } else if (optionsData is List) {
      options = optionsData
          .asMap()
          .entries
          .map((e) => {'key': '${e.key}', 'value': e.value})
          .toList();
    }

    final totalQuestions = widget.totalQuestions;

    final answerRecord = controller.active?.answers.firstWhere(
          (a) => a.questionId == q['id'],
      orElse: () => AnswerRecord(
        questionId: q['id'],
        selectedOptionIds: [],
        updatedAt: DateTime.now(),
      ),
    );

    final selectedOptions =
    (answerRecord?.selectedOptionIds ?? []).cast<String>();

    // Ensure keys exist
    widget.isListScrollable[index] =
        widget.isListScrollable[index] ?? false;
    widget.listAtBottom[index] =
        widget.listAtBottom[index] ?? false;
    widget.scrollControllers[index] ??= ScrollController();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 📘 Header (unchanged)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ScreenUtils.hPad(context),
                vertical: 6,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${index + 1} of $totalQuestions',
                    style: TextStyle(
                      fontSize: ScreenUtils.scaleFont(context, 17),
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      controller.isFlagged(q['id'])
                          ? Icons.flag
                          : Icons.outlined_flag,
                      color: controller.isFlagged(q['id'])
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    onPressed: () => controller.toggleFlag(q['id']),
                  ),
                ],
              ),
            ),

            // 🔘 Progress bar
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ScreenUtils.hPad(context),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (index + 1) / totalQuestions,
                  minHeight: 7,
                  backgroundColor: Colors.grey.shade300,
                  color: const Color(0xFF22C55E),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Question text
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ScreenUtils.hPad(context),
                vertical: 8,
              ),
              child: Text(
                questionText,
                style: TextStyle(
                  fontSize: ScreenUtils.scaleFont(context, 19),
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.3,
                ),
              ),
            ),

            // ANSWERS + SCROLL HINT (unchanged)
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (sn) {
                      final max = sn.metrics.maxScrollExtent;
                      final pixels = sn.metrics.pixels;
                      final scrollable = max > 0;
                      final atBottom = pixels >= max - 10;

                      if (widget.isListScrollable[index] != scrollable ||
                          widget.listAtBottom[index] != atBottom) {
                        setState(() {
                          widget.isListScrollable[index] = scrollable;
                          widget.listAtBottom[index] = atBottom;
                        });
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: widget.scrollControllers[index],
                      padding: EdgeInsets.symmetric(
                        horizontal: ScreenUtils.hPad(context),
                        vertical: 4,
                      ),
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final opt = options[i];
                        final isSelected =
                        selectedOptions.contains(opt['key']);

                        return GestureDetector(
                          onTap: () {
                            if (isMultiple) {
                              if (isSelected) {
                                selectedOptions.remove(opt['key']);
                              } else {
                                selectedOptions.add(opt['key']);
                              }
                              controller.selectMultipleAnswers(
                                q['id'],
                                List<String>.from(selectedOptions),
                              );
                            } else {
                              controller.selectAnswer(q['id'], opt['key']);
                            }
                            setState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: EdgeInsets.symmetric(
                              vertical:
                              ScreenUtils.answerVerticalPadding(context),
                              horizontal:
                              ScreenUtils.answerHorizontalPadding(context),
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFE6F4EA)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF22C55E)
                                    : Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isMultiple
                                      ? (isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank)
                                      : (isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off),
                                  color: isSelected
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey,
                                  size: ScreenUtils.scaleFont(context, 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    opt['value'].toString(),
                                    style: TextStyle(
                                      fontSize:
                                      ScreenUtils.scaleFont(context, 17),
                                      color: isSelected
                                          ? const Color(0xFF22C55E)
                                          : Colors.black87,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  if ((widget.isListScrollable[index] ?? false) &&
                      !(widget.listAtBottom[index] ?? false))
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 400),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double horizontalShift =
                                  constraints.maxWidth * 0.35;

                              return Transform.translate(
                                offset: Offset(horizontalShift, 0),
                                child: Container(
                                  height: 55,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Color(0xFFF9FAFB),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: const [
                                      Icon(Icons.keyboard_arrow_down_rounded,
                                          size: 16,
                                          color: Color(0xFF515151)),
                                      Text(
                                        'Scroll down',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF515151),
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

