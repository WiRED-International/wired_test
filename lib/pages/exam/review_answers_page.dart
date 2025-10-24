import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/exam_controller.dart';
import '../../services/exam_sync_service.dart';
import '../../services/retry_queue_service.dart';

class ReviewAnswersPage extends StatelessWidget {
  final List<Map<String, dynamic>> questions;
  final bool readOnly;

  const ReviewAnswersPage({super.key, required this.questions, this.readOnly = false,});

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
        automaticallyImplyLeading: !readOnly,
        title: Text(
          readOnly ? 'Review (Read-Only)' : 'Review Your Answers',
        ),
        backgroundColor: const Color(0xFF0070C0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              readOnly
                  ? 'Time is up! You can review your answers but cannot change them.'
                  : 'Check your answers before submitting',
              style: TextStyle(
                fontSize: 16,
                color: readOnly ? Colors.redAccent : Colors.black54,
                fontWeight: readOnly ? FontWeight.bold : FontWeight.normal,
              ),
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
            if (!readOnly && unanswered > 0)
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
                    // ✅ Disable tap navigation when readOnly
                    onTap: readOnly
                        ? null
                        : () {
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
                        if (isFlagged)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(Icons.flag,
                                color: Colors.orangeAccent, size: 18),
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
              // 🟡 Hide "Back to Questions" when readOnly
              if (!readOnly)
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Questions'),
                  onPressed: () => Navigator.pop(context, 'back_to_questions'),
                ),
              if (readOnly)
                const SizedBox.shrink(),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                label: Text(
                  readOnly ? 'Submit Exam' : 'Submit Exam',
                  style: const TextStyle(color: Colors.white),
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
            readOnly
                ? '⏰ Exam time expired'
                : '⏰ Time remaining: $formattedTime',
            style: TextStyle(
              color: readOnly ? Colors.redAccent : Colors.black54,
              fontSize: 14,
              fontWeight:
              readOnly ? FontWeight.bold : FontWeight.normal,
            ),
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

    if (confirmed != true || !context.mounted) return;

    // ✅ Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(
                color: Colors.green,
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Text(
                'Submitting Exam…',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final controller = context.read<ExamController>();
      final ok = await controller.submitNow(
        onSubmit: (payload) async {
          final sync = context.read<ExamSyncService>();
          return await sync.submitExam(payload);
        },
        onEnqueue: (payload) async {
          final retry = context.read<RetryQueueService>();
          await retry.enqueueExamSubmission(payload);
        },
      );

      if (context.mounted) Navigator.of(context).pop(); // close spinner

      if (!context.mounted) return;

      if (ok) {
        // ✅ Show success alert
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text('Exam Completed'),
              ],
            ),
            content: const Text(
              'Your exam was submitted successfully!\n\n'
                  'Tap Close to return to the Home page.',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // close dialog
                  Navigator.of(context).popUntil((r) => r.isFirst); // return home
                },
                child: const Text(
                  'Close',
                  style: TextStyle(fontSize: 16, color: Colors.green),
                ),
              ),
            ],
          ),
        );
      } else {
        // ❌ Submission failed — stay on review page
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📡 Submission failed. Please check your connection and try again.'),
            duration: Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // close spinner if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error submitting exam: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
