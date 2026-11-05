class CmeYearCredits {
  const CmeYearCredits({this.year, this.earnedCredits});

  final int? year;
  final int? earnedCredits;

  Map<String, dynamic> toJson() => {
        'year': year,
        'earnedCredits': earnedCredits,
      };
}

class CmeCreditTotals {
  const CmeCreditTotals.unavailable()
      : annualRequirement = null,
        currentYear = const CmeYearCredits(),
        previousYear = const CmeYearCredits();

  const CmeCreditTotals({
    required this.annualRequirement,
    required this.currentYear,
    required this.previousYear,
  });

  final int? annualRequirement;
  final CmeYearCredits currentYear;
  final CmeYearCredits previousYear;

  static int? _integer(dynamic value) => value is num &&
          value.isFinite &&
          value >= 0 &&
          value == value.roundToDouble()
      ? value.toInt()
      : null;

  factory CmeCreditTotals.fromJson(dynamic json) {
    if (json is! Map) return const CmeCreditTotals.unavailable();
    final available = json['status'] == 'available';
    CmeYearCredits parseYear(dynamic data) {
      if (data is! Map) return const CmeYearCredits();
      final year = _integer(data['year']);
      return CmeYearCredits(
        year: year != null && year > 0 ? year : null,
        earnedCredits: available && year != null && year > 0
            ? _integer(data['earnedCredits'])
            : null,
      );
    }

    return CmeCreditTotals(
      annualRequirement: available ? _integer(json['annualRequirement']) : null,
      currentYear: parseYear(json['currentYear']),
      previousYear: parseYear(json['previousYear']),
    );
  }

  Map<String, dynamic> toJson() => {
        'status': currentYear.earnedCredits != null &&
                previousYear.earnedCredits != null &&
                annualRequirement != null
            ? 'available'
            : 'unavailable',
        'annualRequirement': annualRequirement,
        'currentYear': currentYear.toJson(),
        'previousYear': previousYear.toJson(),
      };
}
