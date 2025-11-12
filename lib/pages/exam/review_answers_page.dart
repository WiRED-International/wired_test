import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/exam_models.dart';
import '../../state/exam_controller.dart';
import '../../services/exam_sync_service.dart';
import '../../services/retry_queue_service.dart';

class ReviewAnswersPage extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  const ReviewAnswersPage({super.key, required this.questions});

  @override
  State<ReviewAnswersPage> createState() => _ReviewAnswersPageState();
}

class _ReviewAnswersPageState extends State<ReviewAnswersPage> {
  bool _isSubmitting = false; // 🟢 disable Submit button during submission

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamController>();
    final remaining = controller.remainingSeconds;
    final formattedTime = _formatTime(remaining);

    final total = widget.questions.length;
    final answered = controller.active?.answers.length ?? 0;
    final unanswered = total - answered;
    final flagged = controller.flaggedQuestionsCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Your Answers'),
        backgroundColor: const Color(0xFF0070C0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check your answers before submitting',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 20),

            // ✅ Summary boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSummaryCard('Answered', answered, Colors.green),
                _buildSummaryCard('Unanswered', unanswered, Colors.redAccent),
                _buildSummaryCard('Flagged', flagged, Colors.orangeAccent),
              ],
            ),
            const SizedBox(height: 20),

            // ⚠️ Warning for unanswered
            if (unanswered > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.redAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚠ You have $unanswered unanswered question${unanswered == 1 ? '' : 's'}.\n'
                      'You can still submit, but consider reviewing them first.\n'
                      'Tap on a question to review it.',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '✅ All questions are answered.\n'
                      'You can tap on a question to review or make changes before submitting.',
                  style: TextStyle(color: Colors.green, fontSize: 14),
                ),
              ),

            const SizedBox(height: 20),
            const Text(
              'All Questions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),

            // 📝 Question + Answer list
            Expanded(
              child: ListView.builder(
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
                    onTap: () {
                      Navigator.pop(context, index);
                    },
                    child: Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
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
                              Text(
                                '${index + 1}. ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
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
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Selected: $selectedText',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: hasAnswer
                                            ? Colors.green[700]
                                            : Colors.redAccent,
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
                            child: Icon(
                              Icons.flag,
                              color: Colors.orangeAccent,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // ✅ Bottom buttons
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: const Border(top: BorderSide(color: Colors.black12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Questions'),
                onPressed: () {
                  Navigator.pop(context, 'back_to_questions');
                },
              ),
              ElevatedButton.icon(
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
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: (answered == 0 || _isSubmitting)
                    ? null
                    : () => _confirmSubmission(context),
              ),
            ],
          ),
        ),
      ),

      persistentFooterButtons: [
        Center(
          child: Text(
            '⏰ Time remaining: $formattedTime',
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ),
      ],
    );
  }

  // 🧾 Confirm before final submit
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

    if (confirmed == true && context.mounted) {
      setState(() => _isSubmitting = true); // lock immediately
      await _handleSubmit(context);
    }
  }

  // 🟢 Submit handler with disable + dialog
  Future<void> _handleSubmit(BuildContext context) async {
    setState(() => _isSubmitting = true);

    final controller = context.read<ExamController>();
    final sync = context.read<ExamSyncService>();
    final retry = context.read<RetryQueueService>();

    // ✅ use the correct submit function name
    final success = await controller.submitNow(
      onSubmit: (payload) => sync.submitExam(payload),
      onEnqueue: (payload) => retry.enqueue(payload),
    );

    if (!context.mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      // ✅ submitted successfully
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
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Future.delayed(const Duration(milliseconds: 100), () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                });
              },
              child: const Text(
                'Go to Home',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // 🟠 queued offline
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
              onPressed: () {
                Navigator.of(context).pop();
                Future.delayed(const Duration(milliseconds: 100), () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                });
              },
              child: const Text(
                'Go to Home',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSummaryCard(String label, int count, Color color) {
    return Container(
      width: 100,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ],
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
