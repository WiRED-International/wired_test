import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/exam_models.dart';
import '../models/active_exam_session.dart';
import 'retry_queue_service.dart';
import '../utils/network_utils.dart';
import '../providers/auth_provider.dart';

/// The server accepted the exam; retry local bookkeeping, not the HTTP request.
class ExamAcknowledgmentPersistenceException implements Exception {
  final String sessionId;
  final Object cause;

  ExamAcknowledgmentPersistenceException(this.sessionId, this.cause);

  @override
  String toString() =>
      'Exam $sessionId accepted; local acknowledgment failed: $cause';
}

class ExamSyncService {
  final ValueNotifier<Set<String>> acknowledgedSessions = ValueNotifier({});
  final Box<ExamAttempt> _attempts;
  final Box<PendingSubmission> _retryBox;
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();
  final Map<String, DateTime> _pendingAcknowledgments = {};
  final Map<String, Future<bool>> _submissions = {};
  final Future<bool> Function() _onlineCheck;
  final Stream<List<ConnectivityResult>>? _connectivityChanges;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AuthProvider? _auth;
  String? _token;
  int? _studentId;
  int _authEpoch = 0;
  bool _disposed = false;
  bool _syncRequested = false;
  Future<void>? _syncing;
  Timer? _retryTimer;

  ExamSyncService(this._attempts, this._retryBox,
      {Future<bool> Function()? onlineCheck,
      Stream<List<ConnectivityResult>>? connectivityChanges})
      : _onlineCheck = onlineCheck ?? NetworkUtils.isOnline,
        _connectivityChanges = connectivityChanges {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    _dio = Dio(BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // 🔐 Automatically attach auth token to every request
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra.containsKey('examAuthEpoch')) {
            if (!_authenticated ||
                options.extra['examAuthEpoch'] != _authEpoch) {
              handler.reject(DioException(
                  requestOptions: options,
                  type: DioExceptionType.cancel,
                  message: 'Exam authentication changed before dispatch'));
              return;
            }
            options.headers['Authorization'] =
                'Bearer ${options.extra['examToken']}';
            handler.next(options);
            return;
          }
          final token = await _storage.read(key: 'authToken');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  Dio get dio => _dio;

  bool get _authenticated =>
      !_disposed &&
      _studentId != null &&
      _token != null &&
      _auth != null &&
      !_auth!.isLoading &&
      _auth!.isLoggedIn &&
      _auth!.authToken == _token &&
      !_auth!.isTokenExpired();

  void updateAuthentication(AuthProvider auth) {
    if (_disposed) return;
    _auth = auth;
    final valid = !auth.isLoading && auth.isLoggedIn && !auth.isTokenExpired();
    final student =
        valid ? int.tryParse(auth.getUserIdFromToken() ?? '') : null;
    final token =
        valid && student != null && student > 0 ? auth.authToken : null;
    final changed =
        token != _token || (token == null ? null : student) != _studentId;
    _token = token;
    _studentId = token == null ? null : student;
    if (changed) {
      _authEpoch++;
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    _connectivitySubscription ??=
        (_connectivityChanges ?? Connectivity().onConnectivityChanged).listen(
      (results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          if (_syncing != null) _syncRequested = true;
          _requestSync();
        }
      },
      onError: (Object _) {
        debugPrint('Exam connectivity monitoring failed');
      },
    );
    if (changed && _authenticated) {
      if (_syncing != null) _syncRequested = true;
      _requestSync();
    }
  }

  void _requestSync() {
    unawaited(trySyncNow().catchError((Object _) {
      debugPrint('Exam synchronization deferred; queued submissions retained');
    }));
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_authenticated) return;
    final ownedWork = _retryBox.values.any((entry) {
      try {
        final payload =
            Map<String, dynamic>.from(jsonDecode(entry.payloadJson) as Map);
        final attempt = _matchingAttempt(payload, student: _studentId);
        return attempt != null && entry.attemptId == attempt.attemptId;
      } catch (_) {
        return false;
      }
    });
    if (!ownedWork) return;
    // Network reachability can return without a connectivity-type change.
    _retryTimer = Timer(const Duration(seconds: 30), () {
      _retryTimer = null;
      _requestSync();
    });
  }

  void dispose() {
    _disposed = true;
    _syncRequested = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _authEpoch++;
    unawaited(_connectivitySubscription?.cancel());
  }

  /// Retrieves existing server evidence only; never starts or persists a session.
  Future<ActiveExamSessionResult> getActiveExamSession(int examId) async {
    if (examId <= 0) {
      return const ActiveExamSessionResult(
          ActiveExamSessionOutcome.invalidExamId);
    }
    try {
      final response = await _dio.get<dynamic>(
        '/exams/$examId/active-session',
        options: Options(
            validateStatus: (_) => true, responseType: ResponseType.plain),
      );
      final status = response.statusCode;
      ActiveExamSessionResult result(ActiveExamSessionOutcome outcome) =>
          ActiveExamSessionResult(outcome, statusCode: status);
      if (status == 400) return result(ActiveExamSessionOutcome.invalidExamId);
      if (status == 401)
        return result(ActiveExamSessionOutcome.authenticationFailure);
      if (status != 200 && status != 404 && status != 409) {
        return result(ActiveExamSessionOutcome.serverFailure);
      }
      try {
        final body = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (body is! Map<String, dynamic>) throw const FormatException();
        if (status == 404) {
          // Missing routes and proxy error pages are not evidence of absence.
          return result(body.length == 1 &&
                  body['message'] == 'Active exam session not found'
              ? ActiveExamSessionOutcome.noActiveSession
              : ActiveExamSessionOutcome.malformedResponse);
        }
        if (status == 409) {
          switch (body['code']) {
            case 'MULTIPLE_ACTIVE_SESSIONS':
              return result(ActiveExamSessionOutcome.multipleActiveSessions);
            case 'ORIGINAL_QUESTIONS_UNAVAILABLE':
              return result(
                  ActiveExamSessionOutcome.originalQuestionsUnavailable);
            default:
              return result(ActiveExamSessionOutcome.malformedResponse);
          }
        }
        return ActiveExamSessionResult(ActiveExamSessionOutcome.recoverable,
            statusCode: status,
            session: ActiveExamSession.fromJson(body, requestedExamId: examId));
      } catch (_) {
        return result(ActiveExamSessionOutcome.malformedResponse);
      }
    } on DioException catch (error) {
      return ActiveExamSessionResult(
        error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.sendTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.connectionError
            ? ActiveExamSessionOutcome.networkFailure
            : ActiveExamSessionOutcome.serverFailure,
        statusCode: error.response?.statusCode,
      );
    } catch (_) {
      return const ActiveExamSessionResult(
          ActiveExamSessionOutcome.serverFailure);
    }
  }

  /// 🕒 Auto-sync on app open
  Future<void> autoSyncOnLaunch() async {
    await trySyncNow();
  }

  /// 🔁 Retry queue flush
  Future<void> trySyncNow() {
    if (!_authenticated) return Future.value();
    _retryTimer?.cancel();
    _retryTimer = null;
    final running = _syncing;
    if (running != null) return running;
    _syncRequested = true;
    final result = _flushQueued();
    _syncing = result;
    result.then<void>((_) {
      _syncing = null;
      if (_syncRequested && _authenticated) {
        _requestSync();
      } else {
        _scheduleRetry();
      }
    }, onError: (Object _) {
      _syncing = null;
      _scheduleRetry();
    });
    return result;
  }

  Future<void> _flushQueued() async {
    while (_syncRequested && _authenticated) {
      _syncRequested = false;
      final student = _studentId!;
      final epoch = _authEpoch;
      if (!await _onlineCheck()) {
        if (_syncRequested) continue;
        return;
      }
      if (!_authenticated || epoch != _authEpoch) continue;
      final entries = _retryBox.values.toList()
        ..sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
      final seen = <String>{};
      for (final entry in entries) {
        if (!_authenticated || epoch != _authEpoch) break;
        try {
          final payload =
              Map<String, dynamic>.from(jsonDecode(entry.payloadJson) as Map);
          final attempt = _matchingAttempt(payload, student: student);
          if (attempt == null ||
              entry.attemptId != attempt.attemptId ||
              !seen.add(attempt.attemptId)) {
            continue;
          }
          final accepted = await _submitOnce(payload, automatic: true);
          if (!accepted && entry.isInBox) {
            await RetryQueueService(_retryBox).markTried(entry);
          }
        } catch (_) {
          // A bad entry or failed local acknowledgment must not discard the
          // submission or prevent other owned entries from being considered.
          debugPrint(
              'Queued exam retained for a later synchronization attempt');
        }
      }
    }
  }

  /// 🧩 1️⃣ Start a new exam session
  Future<Map<String, dynamic>?> startExamSession(int examId) async {
    try {
      final res = await _dio.post('/exams/$examId/start-session');

      if (res.statusCode == 201 || res.statusCode == 200) {
        if (res.data is String) {
          return jsonDecode(res.data);
        } else if (res.data is Map<String, dynamic>) {
          return res.data;
        }
      }

      return null;
    } catch (e) {
      print('❌ Error starting exam session: $e');
      return null;
    }
  }

  /// 🧭 Get currently available exam (returns exam info or null)
  Future<Map<String, dynamic>?> getAvailableExam() async {
    try {
      final res = await _dio.get('/exams/available');
      if (res.statusCode == 200) return res.data;
      return null;
    } catch (e) {
      print('Error fetching available exam: $e');
      return null;
    }
  }

  ExamAttempt? _matchingAttempt(Map<String, dynamic> payload, {int? student}) {
    final id = (payload['session_id'] ?? payload['attempt_id'])?.toString();
    if (id == null ||
        id.isEmpty ||
        (payload['attempt_id'] != null &&
            payload['attempt_id'].toString() != id) ||
        (payload['session_id'] != null &&
            payload['session_id'].toString() != id)) {
      return null;
    }
    final attempt = _attempts.get(id);
    if (attempt == null ||
        attempt.attemptId != id ||
        (student != null && attempt.userId != student) ||
        (payload['user_id'] != null && payload['user_id'] != attempt.userId) ||
        (payload['exam_id'] != null && payload['exam_id'] != attempt.examId)) {
      return null;
    }
    return attempt;
  }

  Future<bool> _submitOnce(Map<String, dynamic> payload,
      {bool automatic = false}) {
    if (_disposed || (_auth != null && !_authenticated)) {
      return Future.value(false);
    }
    final attempt = _matchingAttempt(payload, student: _studentId);
    if (attempt == null) return Future.value(false);
    final id = attempt.attemptId;
    final existing = _submissions[id];
    if (existing != null) return existing;
    final result = _performSubmission(payload,
        automatic: automatic,
        epoch: _auth == null ? null : _authEpoch,
        token: _token);
    _submissions[id] = result;
    result.then<void>((_) => _submissions.remove(id), onError: (Object _) {
      _submissions.remove(id);
    });
    return result;
  }

  /// 🔹 Main online submit called from ExamController
  /// Also passes through normalized answers as-is.
  Future<bool> submitExam(Map<String, dynamic> payload) => _submitOnce(payload);

  Future<bool> _performSubmission(Map<String, dynamic> payload,
      {required bool automatic,
      required int? epoch,
      required String? token}) async {
    try {
      final sessionId = payload['session_id'] ?? payload['attempt_id'];
      if (sessionId == null) {
        debugPrint('❌ [submitExam] Missing session_id/attempt_id in payload');
        return false;
      }

      final answers = payload['answers'] as List<dynamic>? ?? [];
      final examId = payload['exam_id'];

      if (answers.isEmpty) {
        debugPrint('❌ [submitExam] Empty answers list');
        return false;
      }

      final id = sessionId.toString();
      final attempt = _matchingAttempt(payload);
      if (attempt == null) return false;
      if (attempt.submitted && attempt.submittedAt != null) {
        await _persistAcknowledgment(id, payload, attempt.submittedAt!);
        return true;
      }
      final pending = _pendingAcknowledgments[id];
      if (pending != null) {
        await _persistAcknowledgment(id, payload, pending);
        return true;
      }

      final res = await _dio.put(
        '/exam-sessions/$sessionId/submit',
        data: {
          'answers': answers,
          // Retry only the known session. Omitting exam_id also avoids the
          // development backend's missing-session creation fallback.
          if (!automatic && examId != null) 'exam_id': examId,
        },
        options: Options(
            validateStatus: (_) => true,
            followRedirects: false,
            extra: epoch == null
                ? null
                : {'examAuthEpoch': epoch, 'examToken': token}),
      );

      dynamic body = res.data;
      if (body is String) {
        try {
          body = jsonDecode(body);
        } catch (_) {
          body = null;
        }
      }
      final alreadySubmitted = res.statusCode == 400 &&
          body is Map &&
          body.length == 1 &&
          body['message'] == 'Exam already submitted';
      final matchingResponse = body is Map &&
          body['message'] == 'Exam submitted successfully' &&
          body['resolved_session_id']?.toString() == id;
      if ((res.statusCode == 200 && matchingResponse) || alreadySubmitted) {
        final acceptedAt = DateTime.now();
        _pendingAcknowledgments[id] = acceptedAt;
        await _persistAcknowledgment(id, payload, acceptedAt);
        debugPrint('✅ [ExamSyncService] Submission succeeded');
        return true;
      } else {
        debugPrint('⚠️ [ExamSyncService] Submission failed: ${res.statusCode}');
        return false;
      }
    } on ExamAcknowledgmentPersistenceException {
      rethrow;
    } catch (e) {
      debugPrint('❌ [ExamSyncService] Submission failed: $e');
      return false;
    }
  }

  Future<void> _persistAcknowledgment(String sessionId,
      Map<String, dynamic> payload, DateTime acceptedAt) async {
    try {
      final attempt = _attempts.get(sessionId);
      if (attempt == null ||
          attempt.attemptId != sessionId ||
          (payload['attempt_id'] != null &&
              payload['attempt_id'].toString() != sessionId) ||
          (payload['exam_id'] != null &&
              payload['exam_id'] != attempt.examId)) {
        throw StateError(
            'No matching local attempt for accepted session $sessionId');
      }
      final wasSubmitted = attempt.submitted;
      final previousTime = attempt.submittedAt;
      attempt.submitted = true;
      attempt.submittedAt ??= acceptedAt;
      try {
        await attempt.save();
      } catch (_) {
        // Do not let an optimistic in-memory flag masquerade as a completed save.
        attempt.submitted = wasSubmitted;
        attempt.submittedAt = previousTime;
        rethrow;
      }
      // Publish only after the acknowledgment is durably saved, before cleanup.
      if (!_disposed) {
        acknowledgedSessions.value = {...acknowledgedSessions.value, sessionId};
      }
      _pendingAcknowledgments.remove(sessionId);
      // A durable acknowledgment is the deletion boundary, including legacy
      // timestamp-keyed duplicates. Explicitly conflicting identities survive.
      for (final entry in _retryBox.values.toList()) {
        if (entry.attemptId != sessionId) continue;
        try {
          final saved = jsonDecode(entry.payloadJson);
          if (saved is! Map ||
              (saved['user_id'] != null &&
                  saved['user_id'] != attempt.userId) ||
              (saved['exam_id'] != null &&
                  saved['exam_id'] != attempt.examId) ||
              (saved['attempt_id'] != null &&
                  saved['attempt_id'].toString() != sessionId) ||
              (saved['session_id'] != null &&
                  saved['session_id'].toString() != sessionId)) {
            continue;
          }
        } catch (_) {
          continue;
        }
        await entry.delete();
      }
    } catch (error) {
      throw ExamAcknowledgmentPersistenceException(sessionId, error);
    }
  }

  Future<List<Map<String, dynamic>>> fetchAssignedExams() async {
    try {
      final res = await _dio.get('/exams/assigned');
      if (res.statusCode == 200 && res.data is List) {
        return List<Map<String, dynamic>>.from(res.data);
      }
    } catch (e) {
      debugPrint('Error fetching assigned exams: $e');
    }
    return [];
  }
}
