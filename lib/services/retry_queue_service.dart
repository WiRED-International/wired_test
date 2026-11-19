import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/exam_models.dart';

class RetryQueueService {
  final Box<PendingSubmission> _retryBox;
  static final _writes = Expando<Future<void>>();
  RetryQueueService(this._retryBox);

  bool containsSession(String sessionId) =>
      _retryBox.values.any((entry) => entry.attemptId == sessionId);

  bool containsExam(int examId, int userId) => _retryBox.values.any((entry) {
        try {
          final payload = jsonDecode(entry.payloadJson);
          return payload is Map &&
              payload['exam_id'] == examId &&
              (payload['user_id'] == null || payload['user_id'] == userId);
        } catch (_) {
          return false;
        }
      });

  /// 🟥 NEVER use this directly from submission logic
  /// Internal: always queue with proper metadata
  Future<void> _enqueueInternal(Map<String, dynamic> payload) {
    final attemptId =
        payload['attempt_id']?.toString() ?? payload['session_id']?.toString();
    if (attemptId == null ||
        attemptId.trim().isEmpty ||
        attemptId != attemptId.trim() ||
        (payload['session_id'] != null &&
            payload['session_id'].toString() != attemptId)) {
      return Future.error(StateError('A consistent exam session is required'));
    }
    final frozenPayload = jsonEncode(payload);
    // Serialize across service instances sharing this box. Legacy timestamp keys
    // remain untouched; their session identity still prevents another enqueue.
    final write = (_writes[_retryBox] ?? Future<void>.value()).then((_) async {
      if (containsSession(attemptId)) return;
      if (_retryBox.containsKey(attemptId)) {
        throw StateError('An existing queue entry uses this key');
      }
      await _retryBox.put(
          attemptId,
          PendingSubmission(
            attemptId: attemptId,
            payloadJson: frozenPayload,
            retryCount: 0,
            enqueuedAt: DateTime.now(),
          ));
    });
    _writes[_retryBox] = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  /// 🟡 Backwards compatible: keep original enqueue()
  /// The caller must obtain the student's submission confirmation first.
  Future<void> enqueue(Map<String, dynamic> payload) async {
    await _enqueueInternal(payload);
  }

  /// Keep the failed submission queued and record the retry.
  Future<void> markTried(PendingSubmission p) async {
    p.retryCount++;
    await p.save();
  }
}
