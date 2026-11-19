/// Retrieval is informational: no outcome authorizes a new start request.
enum ActiveExamSessionOutcome {
  recoverable,
  invalidExamId,
  authenticationFailure,
  noActiveSession,
  multipleActiveSessions,
  originalQuestionsUnavailable,
  malformedResponse,
  networkFailure,
  serverFailure,
}

class ActiveExamSessionResult {
  final ActiveExamSessionOutcome outcome;
  final ActiveExamSession? session;
  final int? statusCode;

  const ActiveExamSessionResult(this.outcome, {this.session, this.statusCode});
}

class ActiveExamSession {
  final String sessionId;
  final int examId;
  final DateTime startedAt;
  final int durationMinutes;
  int get durationSeconds => durationMinutes * 60;

  /// Existing question-map format, in the server's original question order.
  /// Only learner-facing fields are retained.
  final List<Map<String, dynamic>> questions;

  const ActiveExamSession._(this.sessionId, this.examId, this.startedAt,
      this.durationMinutes, this.questions);

  factory ActiveExamSession.fromJson(Map<String, dynamic> json,
      {required int requestedExamId}) {
    Never invalid() => throw const FormatException('Invalid active session');
    final id = json['session_id'];
    if (!((id is int && id > 0) ||
        (id is String && id.trim().isNotEmpty && id == id.trim()))) {
      invalid();
    }
    final examId = json['exam_id'];
    if (examId is! int || examId != requestedExamId) invalid();
    final exam = json['exam'];
    if (exam != null &&
        (exam is! Map || (exam['id'] != null && exam['id'] != examId))) {
      invalid();
    }
    final nestedDuration = exam is Map ? exam['duration_minutes'] : null;
    final duration = json['duration_minutes'] ?? nestedDuration;
    if (duration is! int ||
        duration <= 0 ||
        (nestedDuration != null && nestedDuration != duration)) {
      invalid();
    }
    if (json['duration_seconds'] != null &&
        json['duration_seconds'] != duration * 60) {
      invalid();
    }
    final rawStart = json['started_at'];
    if (rawStart is! String ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(rawStart)) {
      invalid();
    }
    final start = DateTime.tryParse(rawStart);
    if (start == null) invalid();
    final rawQuestions = json['questions'];
    if (rawQuestions is! List || rawQuestions.isEmpty) invalid();
    final ids = <int>{};
    final questions = <Map<String, dynamic>>[];
    for (final raw in rawQuestions) {
      if (raw is! Map) invalid();
      final questionId = raw['id'];
      final text = raw['question_text'] ?? raw['text'];
      final options = raw['options'];
      final order = raw['option_order'];
      if (questionId is! int ||
          questionId <= 0 ||
          !ids.add(questionId) ||
          text is! String ||
          text.trim().isEmpty ||
          options is! Map ||
          options.isEmpty ||
          options.keys.any((key) => key is! String || key.isEmpty) ||
          options.values.any((value) => value is! String) ||
          order is! List ||
          order.any((key) => key is! String) ||
          order.length != options.length ||
          order.toSet().length != order.length ||
          order.any((key) => !options.containsKey(key))) {
        invalid();
      }
      final type = raw['question_type'];
      if (type != null && type is! String) invalid();
      // Rebuild the same options map in explicit order for existing consumers.
      questions.add(Map<String, dynamic>.unmodifiable({
        'id': questionId,
        'question_text': text,
        if (type != null) 'question_type': type,
        'options': Map<String, dynamic>.unmodifiable({
          for (final key in order) key as String: options[key],
        }),
        'option_order': List<String>.unmodifiable(order.cast<String>()),
      }));
    }
    return ActiveExamSession._(id.toString(), examId, start, duration,
        List<Map<String, dynamic>>.unmodifiable(questions));
  }
}
