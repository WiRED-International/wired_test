import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/models/quiz_result_validation.dart';

void main() {
  test('accepts numeric scores inclusively from zero to 100', () {
    for (final value in [0, 0.0, 0.5, 55, 99.99, 100, '0', ' 75.25 ']) {
      expect(validQuizScore(value), isNotNull, reason: '$value');
    }
  });
  test('rejects missing, malformed, nonfinite and out-of-range scores', () {
    for (final value in [
      null,
      '',
      'wrong',
      false,
      [],
      {},
      -1,
      100.01,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      'NaN',
      'Infinity'
    ]) {
      expect(validQuizScore(value), isNull, reason: '$value');
    }
  });
  test('preserves positive external numeric IDs without imposing width', () {
    for (final value in ['1234', '00123456', 1234]) {
      expect(validQuizModuleId(value), value.toString());
    }
    for (final value in [
      null,
      '',
      ' ',
      'unknown',
      'null',
      0,
      '0000',
      -1,
      'abc1234',
      '../1234',
      '12.34',
      1234.0,
      true,
      {}
    ]) {
      expect(validQuizModuleId(value), isNull, reason: '$value');
    }
  });
}
