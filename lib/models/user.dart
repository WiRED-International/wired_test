import '../utils/functions.dart';

class User {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? role;
  final String? country;
  final String? organization;
  final String? dateJoined;
  final List<dynamic>? quizScores;
  final int creditsEarned;
  final int totalCredits;

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.country,
    required this.organization,
    required this.dateJoined,
    required this.quizScores,
    this.totalCredits = 50,
  }) : creditsEarned = calculateCredits(quizScores ?? []);

  factory User.fromJson(Map<String, dynamic> json) {
    final parsedQuizScores = (json['quizScores'] as List<dynamic>?)?.map((q) {
      final module = q['module'] ?? {};
      return {
        ...q,
        'credit_type': module['credit_type'] ?? 'none',
      };
    }).toList() ?? [];

    return User(
      id: json['id'],
      firstName: json['first_name'] ?? 'Unknown',
      lastName: json['last_name'] ?? 'Unknown',
      email: json['email'] ?? 'No email',
      role: json['role']?['name'] ?? 'Unknown Role',
      country: json['country']?['name'] ?? 'Unknown',
      organization: json['organization']?['name'] ?? 'Unknown',
      dateJoined: json['createdAt'] ?? 'Unknown Date',
      quizScores: parsedQuizScores,
      totalCredits:
      (json['totalCredits'] ?? json['total_credits'] ?? 50).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'role': role,
    'country': country,
    'organization': organization,
    'dateJoined': dateJoined,
    'quizScores': quizScores,
    'creditsEarned': creditsEarned,
    'totalCredits': totalCredits,
  };
}