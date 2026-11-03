import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class CmeAwardProvider with ChangeNotifier {
  CmeAwardProvider({
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
  Set<int> _creditedModuleIds = {};
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _refreshRequested = false;
  bool _disposed = false;
  int _session = 0;
  int? _lookupSession;
  Future<void>? _operation;
  String? _currentAuthToken;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  void syncAuthToken(String? token) {
    if (_currentAuthToken == token) return;
    _currentAuthToken = token;
    _session++;
    _creditedModuleIds = {};
    _hasLoaded = false;
    // An active lookup is bounded. Its owner will service the new session next,
    // even if the new page's initial request arrives while it is still running.
    if (_operation != null) _refreshRequested = token != null;
    notifyListeners();
  }

  bool hasEarnedCredit(int moduleId) => _creditedModuleIds.contains(moduleId);

  /// Best-effort refresh: errors never escape to a successful score submission.
  /// Normal callers share active work. Forced callers coalesce into a subsequent
  /// lookup, rather than accepting a snapshot started before their request.
  Future<void> fetchAwardedModules({bool forceRefresh = false}) {
    if (_disposed || _currentAuthToken == null) return Future.value();
    if (forceRefresh) _hasLoaded = false;
    if (_operation != null) {
      if (forceRefresh || _lookupSession != _session) _refreshRequested = true;
      return _operation!;
    }
    if (_hasLoaded && !forceRefresh) return Future.value();
    final completion = Completer<void>();
    _operation = completion.future; // Reserve before storage I/O or observers.
    _isLoading = true;
    unawaited(_drain(completion));
    notifyListeners();
    return completion.future;
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      do {
        _refreshRequested = false;
        final token = _currentAuthToken;
        if (_disposed || token == null) break;
        _lookupSession = _session;
        await _lookup(token, _session);
      } while (_refreshRequested && !_disposed);
    } finally {
      _operation = null;
      _isLoading = false;
      if (!_disposed) notifyListeners();
      completion.complete();
    }
  }

  Future<void> _lookup(String token, int session) async {
    http.Client? client;
    var finished = false;
    bool current() => !finished && !_disposed && session == _session;
    Future<void> lookup() async {
      // Include secure storage in the deadline and error boundary. A late read
      // must not start a request after its attempt has timed out.
      final storedToken = await _readToken();
      if (!current() || storedToken != token) return;
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
      client = _clientFactory();
      final response = await client!.get(
        Uri.parse('$apiBaseUrl/quiz-scores/cme-awarded-modules'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
      );
      if (!current() || _refreshRequested) return;
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch CME awards: ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final ids = data['credited_module_ids'] as List<dynamic>;
      _creditedModuleIds = ids.map((id) => (id as num).toInt()).toSet();
      _hasLoaded = true;
    }

    try {
      await lookup().timeout(requestTimeout);
    } catch (error) {
      debugPrint('Failed to fetch CME awards: $error');
    } finally {
      finished = true; // Ignore late responses, including after token reuse.
      try {
        client?.close();
      } catch (error) {
        debugPrint('Failed to close CME award request: $error');
      }
    }
  }

  void clear() {
    _session++;
    _creditedModuleIds = {};
    _hasLoaded = false;
    _refreshRequested = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _refreshRequested = false;
    super.dispose();
  }
}
