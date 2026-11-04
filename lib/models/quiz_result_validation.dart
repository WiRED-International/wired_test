/// Shared validation for module results and manually submitted pending scores.
double? validQuizScore(Object? value) {
  final double? score;
  if (value is num) {
    score = value.toDouble();
  } else if (value is String) {
    score = double.tryParse(value.trim());
  } else {
    return null;
  }
  return score != null && score.isFinite && score >= 0 && score <= 100
      ? score
      : null;
}

/// Keep external IDs (including leading zeros) intact. Both legacy and compiler
/// results use positive numeric identifiers; no fixed width is imposed here.
String? validQuizModuleId(Object? value) {
  if (value is! String && value is! int) return null;
  final id = value.toString().trim();
  return RegExp(r'^[0-9]+$').hasMatch(id) && id.contains(RegExp(r'[1-9]'))
      ? id
      : null;
}
