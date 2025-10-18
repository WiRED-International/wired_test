import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/exam_controller.dart';
import '../../services/exam_sync_service.dart';
import '../../services/retry_queue_service.dart';

class ReviewAnswersPage extends StatelessWidget {
  final List<Map<String, dynamic>> questions;

  const ReviewAnswersPage({super.key, required this.questions});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamController>();
    final remaining = controller.remainingSeconds;
    final formattedTime = _formatTime(remaining);

    final total = questions.length;
    final answered = controller.active?.answers.length ?? 0;
    final unanswered = total - answered;
    final flagged = controller.flaggedQuestionsCount; // optional future flag feature

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
                      'You can still submit, but consider reviewing them first.',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
              ),

            const SizedBox(height: 20),
            const Text(
              'All Questions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),

            // 🔢 Question buttons grid
            Expanded(
              child: GridView.builder(
                itemCount: questions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final q = questions[index];
                  final isAnswered =
                      controller.active?.answers.any((a) => a.questionId == q['id']) ?? false;
                  final isFlagged = controller.isFlagged(q['id']);

                  final borderColor = isAnswered ? Colors.green : Colors.redAccent;

                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context, index);
                    },
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: borderColor, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: borderColor,
                              ),
                            ),
                          ),
                        ),

                        // 🏳 Flag overlay
                        if (isFlagged)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(
                              Icons.flag,
                              color: Colors.orangeAccent,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),

      // 🟢 Bottom bar
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
                icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                label: const Text(
                  'Submit Exam',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: answered == 0 ? null : () => _confirmSubmission(context),
              ),
            ],
          ),
        ),
      ),

      // ⏱️ Footer timer
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

  // 🧾 Confirmation dialog before final submit
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
      await _handleSubmit(context);
    }
  }

  Future<void> _handleSubmit(BuildContext context) async {
    final controller = context.read<ExamController>();
    final sync = context.read<ExamSyncService>();
    final retry = context.read<RetryQueueService>();

    await controller.submitNow(
      onSubmit: (payload) => sync.submitPayload(payload),
      onEnqueue: (payload) => retry.enqueue(payload),
    );

    if (controller.active?.submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Exam submitted successfully!')),
      );
      Navigator.pop(context, 'submitted');
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📡 Offline: submission queued for retry')),
      );
      Navigator.pop(context, 'submitted');
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
          Text('$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              )),
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
