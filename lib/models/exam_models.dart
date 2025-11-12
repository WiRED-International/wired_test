import 'package:hive/hive.dart';
part 'exam_models.g.dart';

@HiveType(typeId: 1)
class ExamAttempt extends HiveObject {
  @HiveField(0)
  String attemptId; // UUID from backend or generated locally then reconciled
  @HiveField(1)
  int examId;
  @HiveField(2)
  int userId;
  @HiveField(3)
  DateTime startedAt;
  @HiveField(4)
  DateTime? submittedAt;
  @HiveField(5)
  int durationSeconds; // from backend
  @HiveField(6)
  List<AnswerRecord> answers; // locally maintained
  @HiveField(7)
  bool submitted; // true once confirmed by server
  @HiveField(8)
  Map<String, dynamic> meta; // room for future fields
  @HiveField(9)
  bool isReviewed;

  ExamAttempt({
    required this.attemptId,
    required this.examId,
    required this.userId,
    required this.startedAt,
    this.submittedAt,
    required this.durationSeconds,
    required this.answers,
    this.submitted = false,
    this.meta = const {},
    this.isReviewed = false,
  });
}

@HiveType(typeId: 2)
class AnswerRecord extends HiveObject {
  @HiveField(0)
  int questionId;

  // Backward compatible — single choice still uses this
  @HiveField(1)
  String? selectedOptionId; // old field for single answers

  // multiple-choice support
  @HiveField(2)
  List<String>? selectedOptionIds; // new field for multiple-choice answers

  @HiveField(3)
  DateTime updatedAt;

  AnswerRecord({
    required this.questionId,
    this.selectedOptionId,
    List<String>? selectedOptionIds,
    required this.updatedAt,
  }) : selectedOptionIds = selectedOptionIds ?? [];

  /// Utility: always returns a list (for backend consistency)
  List<String> get normalizedOptions {
    final ids = selectedOptionIds ?? [];
    if (ids.isNotEmpty) {
      return ids;
    } else if (selectedOptionId != null) {
      return [selectedOptionId!];
    } else {
      return <String>[];
    }
  }

  /// Converts this record into JSON ready for POST
  Map<String, dynamic> toJson() => {
    'question_id': questionId,
    'selected_option_ids': normalizedOptions,
  };
}

@HiveType(typeId: 3)
class PendingSubmission extends HiveObject {
  @HiveField(0)
  String attemptId;
  @HiveField(1)
  String payloadJson; // canonical JSON we’ll POST
  @HiveField(2)
  int retryCount;
  @HiveField(3)
  DateTime enqueuedAt;

  PendingSubmission({
    required this.attemptId,
    required this.payloadJson,
    required this.retryCount,
    required this.enqueuedAt,
  });
}
