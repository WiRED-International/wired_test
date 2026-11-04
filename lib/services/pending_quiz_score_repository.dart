import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum PendingScoreRemovalOutcome { removed, alreadyAbsent, changed }

/// One application-scoped instance owns all pending-score storage operations.
/// The queue covers local reads and mutations only, never network requests.
class PendingQuizScoreRepository {
  PendingQuizScoreRepository({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
    Future<void> Function()? delete,
  })  : _read = read ?? (() => _storage.read(key: _key)),
        _write = write ?? ((value) => _storage.write(key: _key, value: value)),
        _delete = delete ?? (() => _storage.delete(key: _key));

  static const _key = 'pending_quiz_scores';
  static const _storage = FlutterSecureStorage();
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final Future<void> Function() _delete;
  Future<void> _tail = Future.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    // Observe errors for the queue while preserving them for the caller.
    _tail =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<Map<String, dynamic>> _readMap() async {
    final raw = await _read();
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Pending quiz scores must be a JSON map');
    }
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (entry.key.isEmpty || value is! Map<String, dynamic>) {
        throw const FormatException('Invalid pending quiz score entry');
      }
      final score = value['score'];
      final parsed = score is num ? score : num.tryParse(score.toString());
      if (parsed == null ||
          !parsed.isFinite ||
          (value.containsKey('module_name') &&
              value['module_name'] is! String) ||
          (value.containsKey('date_saved') && value['date_saved'] is! String)) {
        throw const FormatException('Invalid pending quiz score fields');
      }
    }
    return decoded;
  }

  Future<Map<String, dynamic>> readAll() => _serialize(_readMap);

  /// Compare and remove in the same queue operation. Snapshot before queueing
  /// so later caller mutations cannot change which entry was acknowledged.
  Future<PendingScoreRemovalOutcome> removeIfUnchanged(
      String moduleId, Map<String, dynamic> submittedEntry) {
    final snapshot = jsonDecode(jsonEncode(submittedEntry));
    return _serialize(() async {
      final scores = await _readMap();
      if (!scores.containsKey(moduleId)) {
        return PendingScoreRemovalOutcome.alreadyAbsent;
      }
      if (!_structurallyEqual(scores[moduleId], snapshot)) {
        return PendingScoreRemovalOutcome.changed;
      }
      scores.remove(moduleId);
      if (scores.isEmpty) {
        await _delete();
      } else {
        await _write(jsonEncode(scores));
      }
      return PendingScoreRemovalOutcome.removed;
    });
  }

  static bool _structurallyEqual(dynamic left, dynamic right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every((key) =>
              right.containsKey(key) &&
              _structurallyEqual(left[key], right[key]));
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_structurallyEqual(left[i], right[i])) return false;
      }
      return true;
    }
    return left == right;
  }

  Future<void> save({
    required String moduleId,
    required String moduleName,
    required double score,
  }) =>
      _serialize(() async {
        if (moduleId.isEmpty || !score.isFinite) {
          throw ArgumentError('Invalid pending quiz score');
        }
        final scores = await _readMap();
        scores[moduleId] = {
          ...?scores[moduleId] as Map<String, dynamic>?,
          'module_name': moduleName,
          'score': score,
          'date_saved': DateTime.now().toIso8601String(),
        };
        await _write(jsonEncode(scores));
      });

  /// Unconditional removal for an explicit user-requested deletion.
  Future<void> remove(String moduleId) => _serialize(() async {
        final scores = await _readMap();
        if (!scores.containsKey(moduleId)) return;
        scores.remove(moduleId);
        if (scores.isEmpty) {
          await _delete();
        } else {
          await _write(jsonEncode(scores));
        }
      });
}
