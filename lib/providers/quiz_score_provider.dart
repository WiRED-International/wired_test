import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class QuizScoreProvider with ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> _quizScores = [];

  List<Map<String, dynamic>> get quizScores => _quizScores;

  Future<void> fetchQuizScores() async {
    final token = await _storage.read(key: 'authToken');
    if (token == null) throw Exception('User not logged in');

    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final url = Uri.parse('$apiBaseUrl/quiz-scores');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonList = jsonDecode(response.body) as List<dynamic>;
      _quizScores = jsonList.map<Map<String, dynamic>>((item) {
        final module = item['module'] ?? {};
        return {
          'id': item['id'],
          'user_id': item['user_id'],
          'module_id': item['module_id'],
          'score': item['score'],
          'date_taken': item['date_taken'],
          'module_name': module['name'] ?? 'Unknown Module',
          'credit_type': module['credit_type'] ?? 'none',
          'categories': module['categories'] ?? [],
        };
      }).toList();

      // 🧩 Save latest version of quiz_scores to SecureStorage
      await _storage.write(key: 'quiz_scores', value: jsonEncode(_quizScores));

      debugPrint('📥 Loaded ${quizScores.length} quiz scores from backend');
      for (final s in quizScores.take(10)) {
        debugPrint('→ id=${s['id']} module_id=${s['module_id']} score=${s['score']}');
      }

      notifyListeners(); // 🔥 updates all dependent widgets
    } else {
      throw Exception('Failed to fetch quiz scores: ${response.statusCode}');
    }
  }

  /// 🟢 Called after a user submits a quiz
  void updateScore(Map<String, dynamic> newScore) {
    _quizScores.removeWhere((s) => s['module_id'] == newScore['module_id']);
    _quizScores.add(newScore);
    notifyListeners();
  }

  /// 🔁 Manually trigger refresh when needed
  Future<void> refreshScores() async => fetchQuizScores();
}
