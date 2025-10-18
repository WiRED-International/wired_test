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
  @HiveField(1)
  String? selectedOptionId; // null if unanswered
  @HiveField(2)
  DateTime updatedAt;

  AnswerRecord({
    required this.questionId,
    required this.selectedOptionId,
    required this.updatedAt,
  });
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
