List<String> validateSubmission(Map<String, dynamic> payload) {
  final errors = <String>[];

  bool req(String k) => payload[k] != null;

  if (!req('attempt_id')) errors.add('attempt_id missing');
  if (!req('exam_id')) errors.add('exam_id missing');
  if (!req('user_id')) errors.add('user_id missing');
  if (!req('answers')) errors.add('answers missing');

  final answers = (payload['answers'] as List?) ?? [];
  if (answers.isEmpty) errors.add('answers empty');

  for (final a in answers) {
    if (a is! Map) {
      errors.add('answer malformed');
      continue;
    }
    if (a['question_id'] == null) errors.add('question_id missing');
    // selected_option_id can be null if you allow blank answers; enforce if required:
    // if (a['selected_option_id'] == null) errors.add('selected_option_id missing');
  }

  // Optional: sanity checks
  // e.g., no duplicate questionIds, timestamps ISO format, etc.

  return errors;
}