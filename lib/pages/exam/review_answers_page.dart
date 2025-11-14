import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/exam_models.dart';
import '../../state/exam_controller.dart';
import '../../services/exam_sync_service.dart';
import '../../services/retry_queue_service.dart';
import '../../utils/screen_utils.dart';

class ReviewAnswersPage extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  const ReviewAnswersPage({super.key, required this.questions});

  @override
  State<ReviewAnswersPage> createState() => _ReviewAnswersPageState();
}

class _ReviewAnswersPageState extends State<ReviewAnswersPage> {
  bool _isSubmitting = false;

  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---------- MAIN BUILD ----------
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortest = media.size.shortestSide;
    final landscape = media.orientation == Orientation.landscape;
    final tablet = ScreenUtils.isTablet(context);
    final titleFont = ScreenUtils.scaleFont(context, 18);
    final cardFont = ScreenUtils.scaleFont(context, 14);
    final answerFont = ScreenUtils.scaleFont(context, 13.5);
    final isLandscape = media.orientation == Orientation.landscape;

    final controller = context.watch<ExamController>();
    final remaining = controller.remainingSeconds;

    final total = widget.questions.length;
    final answered = controller.active?.answers.length ?? 0;
    final unanswered = total - answered;
    final flagged = controller.flaggedQuestionsCount;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0070C0),
        automaticallyImplyLeading: false,
        elevation: 0,
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Review Your Answers',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleFont,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                Icon(Icons.access_time,
                    color: Colors.white, size: ScreenUtils.scaleFont(context, 16)),
                const SizedBox(width: 4),
                Text(
                  _formatTime(remaining),
                  style: TextStyle(
                    fontSize: ScreenUtils.scaleFont(context, 16),
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      // ---------------- BODY (PORTRAIT / LANDSCAPE) ----------------
      body: landscape
          ? _buildLandscapeLayout(
          context, shortest, cardFont, answerFont, answered, unanswered, flagged, isLandscape, controller)
          : _buildPortraitLayout(
          context, shortest, cardFont, answerFont, answered, unanswered, flagged, controller),

      // ---------------- BOTTOM ACTIONS ----------------
      bottomNavigationBar: _buildBottomButtons(context, shortest, cardFont, answered: answered,),
    );
  }

  // ===============================================================
  //                         PORTRAIT MODE
  // ===============================================================
  Widget _buildPortraitLayout(
      BuildContext context,
      double shortest,
      double cardFont,
      double answerFont,
      int answered,
      int unanswered,
      int flagged,
      ExamController controller) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SUMMARY ROWS — same as before
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSummaryCard('Answered', answered, Colors.green),
              _buildSummaryCard('Unanswered', unanswered, Colors.redAccent),
              _buildSummaryCard('Flagged', flagged, Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 20),

          _buildWarningBox(shortest, answerFont, unanswered),
          const SizedBox(height: 20),

          Text('All Questions',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: ScreenUtils.scaleFont(context, 15),
              )),
          const SizedBox(height: 10),

          Expanded(
            child: _buildQuestionList(
              context,
              shortest,
              cardFont,
              answerFont,
              controller,
            ),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  //                         LANDSCAPE MODE
  // ===============================================================
  Widget _buildLandscapeLayout(
      BuildContext context,
      double shortest,
      double cardFont,
      double answerFont,
      int answered,
      int unanswered,
      int flagged,
      bool isLandscape,
      ExamController controller) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // ---------- LEFT PANEL ----------
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isLandscape
                      ? Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildSummaryCard('Answered', answered, Colors.green),
                      _buildSummaryCard('Unanswered', unanswered, Colors.redAccent),
                      _buildSummaryCard('Flagged', flagged, Colors.orangeAccent),
                    ],
                  )
                      : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSummaryCard('Answered', answered, Colors.green),
                      _buildSummaryCard('Unanswered', unanswered, Colors.redAccent),
                      _buildSummaryCard('Flagged', flagged, Colors.orangeAccent),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _buildWarningBox(shortest, answerFont, unanswered),
                  const SizedBox(height: 20),

                  Text('All Questions',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: ScreenUtils.scaleFont(context, 16),
                      )),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // ---------- RIGHT PANEL ----------
          Expanded(
            flex: 6,
            child: _buildQuestionList(
              context,
              shortest,
              cardFont,
              answerFont,
              controller,
            ),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  //                    QUESTION LIST (SHARED)
  // ===============================================================
  Widget _buildQuestionList(
      BuildContext context,
      double shortest,
      double cardFont,
      double answerFont,
      ExamController controller,
      ) {
    return ListView.builder(
      itemCount: widget.questions.length,
      itemBuilder: (context, index) {
        final q = widget.questions[index];
        final isFlagged = controller.isFlagged(q['id']);

        AnswerRecord? answerRecord;
        final attempt = controller.active;

        if (attempt != null) {
          for (final a in attempt.answers) {
            if (a.questionId == q['id']) {
              answerRecord = a;
              break;
            }
          }
        }

        final selected = answerRecord?.normalizedOptions ?? [];
        final hasAnswer = selected.isNotEmpty;

        final selectedText = hasAnswer
            ? selected
            .map((key) => q['options'][key] ?? key.toUpperCase())
            .join(', ')
            : 'No answer';

        return GestureDetector(
          onTap: () => Navigator.pop(context, index),
          child: Stack(
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.symmetric(
                  vertical: ScreenUtils.answerVerticalPadding(context),
                  horizontal: ScreenUtils.answerHorizontalPadding(context),
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: hasAnswer ? Colors.green : Colors.redAccent,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${index + 1}.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          fontSize: cardFont,
                        ),
                      ),
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q['question_text'] ??
                                q['text'] ??
                                'Untitled question',
                            style: TextStyle(
                              fontSize: cardFont,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                            softWrap: true,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Selected: $selectedText',
                            style: TextStyle(
                              fontSize: answerFont,
                              color:
                              hasAnswer ? Colors.green[700] : Colors.redAccent,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isFlagged)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.flag,
                      color: Colors.orangeAccent, size: 20),
                ),
            ],
          ),
        );
      },
    );
  }

  // ===============================================================
  //                     WARNING BOX (SHARED)
  // ===============================================================
  Widget _buildWarningBox(double shortest, double answerFont, int unanswered) {
    if (unanswered > 0) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: ScreenUtils.answerVerticalPadding(context),
          horizontal: ScreenUtils.answerHorizontalPadding(context),
        ),
        decoration: BoxDecoration(
          color: Colors.red[50],
          border: Border.all(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '⚠ You have $unanswered unanswered question${unanswered == 1 ? '' : 's'}.\n'
              'Tap on a question to review it.',
          style: TextStyle(color: Colors.redAccent, fontSize: answerFont),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: ScreenUtils.answerVerticalPadding(context),
        horizontal: ScreenUtils.answerHorizontalPadding(context),
      ),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '✅ All questions are answered.\n'
            'You can tap on a question to review or make changes before submitting.',
        style: TextStyle(color: Colors.green, fontSize: answerFont),
      ),
    );
  }

  // ===============================================================
  //                  SUMMARY CARD (SHARED)
  // ===============================================================
  Widget _buildSummaryCard(String label, int count, Color color) {
    final tablet = ScreenUtils.isTablet(context);
    final cardW = tablet ? 130.0 : 90.0;
    final cardH = tablet ? 85.0 : 60.0;

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$count',
              style: TextStyle(
                fontSize: ScreenUtils.scaleFont(context, 20),
                fontWeight: FontWeight.bold,
                color: color,
              )),
          Text(label,
              style: TextStyle(
                fontSize: ScreenUtils.scaleFont(context, 13),
                color: Colors.black54,
              )),
        ],
      ),
    );
  }

  // ===============================================================
  //                     SUBMIT + BACK BUTTONS
  // ===============================================================
  Widget _buildBottomButtons(
      BuildContext context,
      double shortest,
      double cardFont, {
        required int answered,
      }) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenUtils.answerVerticalPadding(context),
          vertical: ScreenUtils.answerHorizontalPadding(context),
        ),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: const Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(
                  'Back to Questions',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ScreenUtils.scaleFont(context, 14),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context, 'back_to_questions');
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    vertical: ScreenUtils.answerVerticalPadding(context),
                  ),
                ),
              ),
            ),

            SizedBox(width: shortest * 0.03),

            Expanded(
              child: ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.check_circle_outline, color: Colors.white),
                label: Text(
                  _isSubmitting ? 'Submitting...' : 'Submit Exam',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: ScreenUtils.scaleFont(context, 14),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(
                    vertical: ScreenUtils.answerVerticalPadding(context),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),

                // FIXED
                onPressed: (answered == 0 || _isSubmitting)
                    ? null
                    : () => _confirmSubmission(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  //                   CONFIRM + SUBMIT LOGIC
  //         (UNCHANGED — your original code stays intact)
  // ===============================================================
  Future<void> _confirmSubmission(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Exam?'),
        content: const Text(
          'Are you sure you want to submit? You won’t be able to change your answers after submission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      setState(() => _isSubmitting = true);
      await _handleSubmit(context);
    }
  }

  Future<void> _handleSubmit(BuildContext context) async {
    if (!mounted) return;
    setState(() => _isSubmitting = true);

    final controller = context.read<ExamController>();
    final sync = context.read<ExamSyncService>();
    final retry = context.read<RetryQueueService>();

    final success = await controller.submitNow(
      onSubmit: (payload) => sync.submitExam(payload),
      onEnqueue: (payload) => retry.enqueue(payload),
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (success) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Exam Submitted'),
            ],
          ),
          content: const Text(
            'Your exam was successfully submitted.\n\nTap "Go to Home" to return to the main page.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Go to Home',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    // Offline queued case
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Offline Mode'),
          ],
        ),
        content: const Text(
          'You appear to be offline.\nYour submission has been queued and will retry automatically when you’re back online.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Go to Home',
              style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
