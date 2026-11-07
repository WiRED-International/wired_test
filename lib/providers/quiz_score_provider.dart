import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_provider.dart';

class QuizScoreProvider with ChangeNotifier {
  QuizScoreProvider({
    Future<String?> Function()? readToken,
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _readToken = readToken ?? _readStoredToken,
        _clientFactory = clientFactory ?? http.Client.new {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  static Future<String?> _readStoredToken() =>
      const FlutterSecureStorage().read(key: 'authToken');

  final Future<String?> Function() _readToken;
  final http.Client Function() _clientFactory;
  final Duration requestTimeout;
  AuthProvider? _auth;
  bool _authSynchronized = false;
  String? _authToken;
  int _session = 0;
  int _request = 0;
  bool _disposed = false;
  final _activeClients = Set<http.Client>.identity();

  void _closeClient(http.Client? client) {
    // Remove before closing: disposal and request finalization may both run.
    if (client == null || !_activeClients.remove(client)) return;
    try {
      client.close();
    } catch (_) {
      debugPrint('Unable to close quiz score request');
    }
  }

  // Subscribe to every transition, including logout/login between proxy builds.
  void syncAuthProvider(AuthProvider auth) {
    if (_disposed) return;
    if (!identical(_auth, auth)) {
      _auth?.removeListener(_authChanged);
      _auth = auth;
      auth.addListener(_authChanged);
    }
    _authChanged();
  }

  void _authChanged() {
    final auth = _auth!;
    syncAuthToken(auth.isLoggedIn ? auth.authToken : null);
  }

  void syncAuthToken(String? token) {
    if (_disposed || (_authSynchronized && _authToken == token)) return;
    _authSynchronized = true;
    _authToken = token;
    _session++;
    _request++;
    _quizScores = [];
    isLoading = false;
    notifyListeners();
  }

  bool isLoading = false;
  List<Map<String, dynamic>> _quizScores = [];

  List<Map<String, dynamic>> get quizScores => _quizScores;

  Future<void> fetchQuizScores() async {
    if (_disposed || (_authSynchronized && _authToken == null)) return;
    final session = _session;
    final request = ++_request;
    final sessionToken = _authToken;
    bool owned() => !_disposed && session == _session && request == _request;
    var finished = false;
    bool current() => !finished && owned();
    http.Client? client;

    Future<void> load() async {
      if (!current()) return;
      final token = await _readToken();
      if (!current()) return;
      if (_authSynchronized && token != sessionToken) return;
      if (token == null) throw const _MissingToken();

      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
      final url = Uri.parse('$apiBaseUrl/quiz-scores');
      client = _clientFactory();
      _activeClients.add(client!);
      if (!current()) {
        _closeClient(client);
        return;
      }
      final response = await client!.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (!current()) return;

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
      } else {
        throw Exception('Failed to fetch quiz scores: ${response.statusCode}');
      }
    }

    isLoading = true;
    notifyListeners();
    try {
      await load().timeout(requestTimeout);
    } on _MissingToken {
      // Preserve standalone callers' existing missing-authentication exception.
      rethrow;
    } catch (e) {
      if (current()) debugPrint('Error fetching quiz scores: $e');
    } finally {
      finished = true;
      _closeClient(client);
      if (owned()) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 🟢 Called after a user submits a quiz
  void updateScore(Map<String, dynamic> newScore) {
    if (_disposed) return;
    _quizScores.removeWhere((s) => s['module_id'] == newScore['module_id']);
    _quizScores.add(newScore);
    notifyListeners();
  }

  /// 🔁 Manually trigger refresh when needed
  Future<void> refreshScores() async => fetchQuizScores();

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _request++;
    _auth?.removeListener(_authChanged);
    for (final client in _activeClients.toList()) {
      _closeClient(client);
    }
    super.dispose();
  }
}

class _MissingToken implements Exception {
  const _MissingToken();
  @override
  String toString() => 'Exception: User not logged in';
}
