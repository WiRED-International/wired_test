import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/exam_models.dart';
import '../utils/network_utils.dart';

class RetryQueueService {
  final Box<PendingSubmission> _retryBox;
  RetryQueueService(this._retryBox);

  /// 🟢 Queue ONLY when offline
  Future<bool> enqueueIfOffline(Map<String, dynamic> payload) async {
    final online = await NetworkUtils.isOnline();
    if (online) {
      // Online → DO NOT queue
      return false;
    }

    await _enqueueInternal(payload);
    return true;
  }

  /// 🟥 NEVER use this directly from submission logic
  /// Internal: always queue with proper metadata
  Future<void> _enqueueInternal(Map<String, dynamic> payload) async {
    final attemptId =
        payload['attempt_id']?.toString() ??
            payload['session_id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString();

    // Prevent overwriting older queued submissions
    final key = '$attemptId-${DateTime.now().millisecondsSinceEpoch}';

    await _retryBox.put(
      key,
      PendingSubmission(
        attemptId: attemptId,
        payloadJson: jsonEncode(payload),
        retryCount: 0,
        enqueuedAt: DateTime.now(),
      ),
    );
  }

  /// 🟡 Backwards compatible: keep original enqueue()
  /// BUT mark as deprecated to prevent accidental use.
  @Deprecated('Use enqueueIfOffline instead. This queues without checking network status.')
  Future<void> enqueue(Map<String, dynamic> payload) async {
    await _enqueueInternal(payload);
  }

  /// 🧹 Fetch all queued submissions
  Iterable<PendingSubmission> get all => _retryBox.values;

  /// 🔁 Retry logic
  Future<void> markTried(PendingSubmission p, {required bool success}) async {
    if (success) {
      await p.delete();
    } else {
      // Keep it in the queue, but bump retry count
      p
        ..retryCount = (p.retryCount + 1)
        ..save();
    }
  }
}