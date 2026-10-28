
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class CmeAwardProvider with ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  Set<int> _creditedModuleIds = {};
  bool _isLoading = false;
  bool _hasLoaded = false;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  String? _currentAuthToken;

  void syncAuthToken(String? token) {
    if (_currentAuthToken == token) return;

    _currentAuthToken = token;
    _creditedModuleIds = {};
    _hasLoaded = false;
    notifyListeners();
  }

  bool hasEarnedCredit(int moduleId) {
    return _creditedModuleIds.contains(moduleId);
  }

  Future<void> fetchAwardedModules({bool forceRefresh = false}) async {
    if (_isLoading || (_hasLoaded && !forceRefresh)) {
      return;
    }

    final token = await _storage.read(key: 'authToken');
    if (token != _currentAuthToken) return;

    if (token == null) {
      clear();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final apiBaseUrl =
          dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

      final url = Uri.parse(
        '$apiBaseUrl/quiz-scores/cme-awarded-modules',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch CME awards: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final ids = data['credited_module_ids'] as List<dynamic>;

      // Ignore responses belonging to a previous login session.
      if (token != _currentAuthToken) return;

      _creditedModuleIds = ids.map((id) => (id as num).toInt()).toSet();
      _hasLoaded = true;
    } catch (error) {
      debugPrint('Failed to fetch CME awards: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _creditedModuleIds = {};
    _hasLoaded = false;
    notifyListeners();
  }
}
