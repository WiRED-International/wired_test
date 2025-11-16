import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/exam_models.dart';
import 'retry_queue_service.dart';
import '../utils/network_utils.dart';

class ExamSyncService {
  final Box<ExamAttempt> _attempts;
  final Box<PendingSubmission> _retryBox;
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ExamSyncService(this._attempts, this._retryBox) {
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

  /// 🕒 Auto-sync on app open
  Future<void> autoSyncOnLaunch() async {
    await _submitAnyUnsentAttempts();
    await trySyncNow();
  }

  /// 🔁 Retry queue flush
  Future<void> trySyncNow() async {
    if (!await NetworkUtils.isOnline()) {
      debugPrint('🌐 Retry skipped — still offline');
      return;
    }

    final retryService = RetryQueueService(_retryBox);

    for (final p in retryService.all.toList()) {
      final payload = jsonDecode(p.payloadJson) as Map<String, dynamic>;
      final ok = await submitPayload(payload);
      await retryService.markTried(p, success: ok);
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

  /// 🧩 2️⃣ Submit exam session answers
  Future<bool> submitExamSession(int sessionId, List<Map<String, dynamic>> answers) async {
    try {
      final res = await _dio.put(
        '/exam-sessions/$sessionId/submit',
        data: {'answers': answers},
      );
      return res.statusCode == 200;
    } catch (e) {
      print('Error submitting exam session: $e');
      return false;
    }
  }

  /// 🔹 Used by retry/auto-sync
  Future<bool> submitPayload(Map<String, dynamic> payload) async {
    try {
      final sessionId = payload['attempt_id'] ?? payload['session_id'];
      if (sessionId == null) {
        debugPrint('❌ [submitPayload] Missing session_id/attempt_id in payload');
        return false;
      }

      final answers = payload['answers'] as List<dynamic>? ?? [];
      final examId = payload['exam_id'];

      if (answers.isEmpty) {
        debugPrint('❌ [submitPayload] Empty answers list');
        return false;
      }

      final res = await _dio.put(
        '/exam-sessions/$sessionId/submit',
        data: {
          'answers': answers,
          if (examId != null) 'exam_id': examId,
        },
      );

      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Retry submission failed: $e');
      return false;
    }
  }

  /// 🔹 Main online submit called from ExamController
  /// Also passes through normalized answers as-is.
  Future<bool> submitExam(Map<String, dynamic> payload) async {
    debugPrint('Submitting payload: $payload');
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

      final res = await _dio.put(
        '/exam-sessions/$sessionId/submit',
        data: {
          'answers': answers,
          if (examId != null) 'exam_id': examId,
        },
      );

      if (res.statusCode == 200) {
        debugPrint('✅ [ExamSyncService] Submission succeeded');
        return true;
      } else {
        debugPrint('⚠️ [ExamSyncService] Submission failed: ${res.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [ExamSyncService] Submission failed: $e');
      return false;
    }
  }

  /// 🔹 Handle unsent Hive attempts — ONLY runs if *you* call autoSyncOnLaunch().
  /// Kept for completeness, but no longer automatic.
  Future<void> _submitAnyUnsentAttempts() async {
    if (!await NetworkUtils.isOnline()) {
      debugPrint('🌐 Skipping unsent attempts — offline');
      return;
    }

    final retryService = RetryQueueService(_retryBox);

    final unsent = _attempts.values.where((a) => !a.submitted);

    for (final a in unsent) {
      final answers = a.answers.map((x) {
        final ids =
        (x.selectedOptionIds != null && x.selectedOptionIds!.isNotEmpty)
            ? List<String>.from(x.selectedOptionIds!)
            : (x.selectedOptionId != null && x.selectedOptionId!.isNotEmpty)
            ? [x.selectedOptionId!]
            : <String>[];

        return {
          'question_id': x.questionId,
          'selected_option_ids': ids,
          'updated_at': x.updatedAt.toIso8601String(),
        };
      }).toList();

      final payload = {
        'session_id': a.attemptId,
        'exam_id': a.examId,
        'answers': answers,
      };

      // ✅ Correct call — submitExam exists IN THIS CLASS
      final ok = await submitExam(payload);

      if (ok) {
        a.submitted = true;
        await a.save();
      } else {
        await retryService.enqueue(payload);
      }
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