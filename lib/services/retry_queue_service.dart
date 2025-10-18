import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/exam_models.dart';

class RetryQueueService {
  final Box<PendingSubmission> _retryBox;
  RetryQueueService(this._retryBox);

  // 🔹 Existing enqueue for generic payloads
  Future<void> enqueue(Map<String, dynamic> payload) async {
    final attemptId = payload['attempt_id']?.toString() ??
        payload['session_id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    await _retryBox.put(
      attemptId,
      PendingSubmission(
        attemptId: attemptId,
        payloadJson: jsonEncode(payload),
        retryCount: 0,
        enqueuedAt: DateTime.now(),
      ),
    );
  }

  // ✅ NEW helper: explicit name for exam submissions
  Future<void> enqueueExamSubmission(Map<String, dynamic> payload) async {
    await enqueue(payload);
  }

  Iterable<PendingSubmission> get all => _retryBox.values;

  Future<void> markTried(PendingSubmission p, {required bool success}) async {
    if (success) {
      await p.delete();
    } else {
      p
        ..retryCount = p.retryCount + 1
        ..save();
    }
  }
}