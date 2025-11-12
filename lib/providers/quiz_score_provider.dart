import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class QuizScoreProvider with ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  bool isLoading = false;
  List<Map<String, dynamic>> _quizScores = [];

  List<Map<String, dynamic>> get quizScores => _quizScores;

  Future<void> fetchQuizScores() async {
    final token = await _storage.read(key: 'authToken');
    if (token == null) throw Exception('User not logged in');

    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final url = Uri.parse('$apiBaseUrl/quiz-scores');

    isLoading = true;
    notifyListeners();

    try {
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
          final rawCreditType = module['credit_type'];
          final creditType = rawCreditType != null
              ? rawCreditType.toString().toLowerCase()
              : 'none';

          return {
            'id': item['id'],
            'user_id': item['user_id'],
            'module_id': item['module_id'],
            'score': item['score'],
            'date_taken': item['date_taken'],
            'module': module,
            'module_name': module['name'] ?? 'Unknown Module',
            'credit_type': creditType,
            'categories': module['categories'] ?? [],
          };
        }).toList();

        await _storage.write(
            key: 'quiz_scores',
            value: jsonEncode(_quizScores)
        );
      } else {
        throw Exception('Failed to fetch quiz scores: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching quiz scores: $e');
    } finally {
      // ✅ End loading
      isLoading = false;
      notifyListeners();
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
