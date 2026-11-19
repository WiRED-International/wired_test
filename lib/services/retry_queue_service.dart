import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/exam_models.dart';

class RetryQueueService {
  final Box<PendingSubmission> _retryBox;
  static final _writes = Expando<Future<void>>();
  static final _persistence = Expando<Future<bool>>();

  /// Hive exposes optimistic values before put completes. Loaded entries have
  /// no in-flight write; newly enqueued objects carry their persistence result.
  static Future<bool> waitForPersistence(PendingSubmission entry) =>
      _persistence[entry] ?? Future.value(true);
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
      final entry = PendingSubmission(
        attemptId: attemptId,
        payloadJson: frozenPayload,
        retryCount: 0,
        enqueuedAt: DateTime.now(),
      );
      final persisted = Completer<bool>();
      // Register before put can publish this object in Hive's in-memory values.
      _persistence[entry] = persisted.future;
      try {
        await _retryBox.put(attemptId, entry);
        persisted.complete(true);
      } catch (_) {
        // A sync pass may already hold the optimistic object after rollback.
        persisted.complete(false);
        rethrow;
      }
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
