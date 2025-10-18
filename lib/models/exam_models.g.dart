// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exam_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExamAttemptAdapter extends TypeAdapter<ExamAttempt> {
  @override
  final int typeId = 1;

  @override
  ExamAttempt read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExamAttempt(
      attemptId: fields[0] as String,
      examId: fields[1] as int,
      userId: fields[2] as int,
      startedAt: fields[3] as DateTime,
      submittedAt: fields[4] as DateTime?,
      durationSeconds: fields[5] as int,
      answers: (fields[6] as List).cast<AnswerRecord>(),
      submitted: fields[7] as bool,
      meta: (fields[8] as Map).cast<String, dynamic>(),
      isReviewed: fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ExamAttempt obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.attemptId)
      ..writeByte(1)
      ..write(obj.examId)
      ..writeByte(2)
      ..write(obj.userId)
      ..writeByte(3)
      ..write(obj.startedAt)
      ..writeByte(4)
      ..write(obj.submittedAt)
      ..writeByte(5)
      ..write(obj.durationSeconds)
      ..writeByte(6)
      ..write(obj.answers)
      ..writeByte(7)
      ..write(obj.submitted)
      ..writeByte(8)
      ..write(obj.meta)
      ..writeByte(9)
      ..write(obj.isReviewed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExamAttemptAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AnswerRecordAdapter extends TypeAdapter<AnswerRecord> {
  @override
  final int typeId = 2;

  @override
  AnswerRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AnswerRecord(
      questionId: fields[0] as int,
      selectedOptionId: fields[1] as String?,
      updatedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AnswerRecord obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.questionId)
      ..writeByte(1)
      ..write(obj.selectedOptionId)
      ..writeByte(2)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnswerRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PendingSubmissionAdapter extends TypeAdapter<PendingSubmission> {
  @override
  final int typeId = 3;

  @override
  PendingSubmission read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingSubmission(
      attemptId: fields[0] as String,
      payloadJson: fields[1] as String,
      retryCount: fields[2] as int,
      enqueuedAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PendingSubmission obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.attemptId)
      ..writeByte(1)
      ..write(obj.payloadJson)
      ..writeByte(2)
      ..write(obj.retryCount)
      ..writeByte(3)
      ..write(obj.enqueuedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingSubmissionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
