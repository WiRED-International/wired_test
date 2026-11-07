import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../pages/cme/credits_tracker_info.dart';
import '../pages/cme/login.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoading = true;
  bool _isLoggedIn = false; // Tracks the authentication status
  String? _authToken;
  DateTime? _tokenExpiry;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  Future<void>? _operations;
  bool _disposed = false;

  Future<void> _enqueue(Future<void> Function() operation) {
    final previous = _operations;
    final completion = Completer<void>();
    final queued = completion.future;
    _operations = queued;
    Future<void> run() async {
      if (_disposed) throw StateError('AuthProvider is disposed');
      await operation();
    }

    final result = previous == null ? run() : previous.then((_) => run());
    void release() {
      if (identical(_operations, queued)) _operations = null;
      completion.complete();
    }

    // The queue gate always completes, but callers still receive result errors.
    result.then<void>((_) => release(),
        onError: (Object _, StackTrace __) => release());
    return result;
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get isLoggedIn => _isLoggedIn;
  String? get authToken => _authToken;
  bool get isLoading => _isLoading;

  // Load stored token & expiry on app startup
  Future<void> loadStoredAuthData() => _enqueue(() async {
        _isLoading = true;
        _notifyIfActive();
        try {
          final token = await storage.read(key: 'authToken');
          final expiryString = await storage.read(key: 'tokenExpiry');
          final expiry =
              expiryString == null ? null : DateTime.tryParse(expiryString);
          if (_disposed) return;
          _authToken = token;
          _tokenExpiry = expiry;
          _isLoggedIn = token != null &&
              token.isNotEmpty &&
              expiry != null &&
              !isTokenExpired();
        } catch (_) {
          // Preserve the last committed session and stored data on read failure.
          debugPrint('Unable to restore authentication from secure storage');
        } finally {
          _isLoading = false;
          _notifyIfActive();
        }
      });

  // Persist before publishing a login. The two keys are not atomic: a failed
  // second write may leave partial storage; errors propagate without rollback.
  Future<void> logIn(String authToken, DateTime expiry) => _enqueue(() async {
        final expiryUtc = expiry.toUtc();
        await storage.write(key: 'authToken', value: authToken);
        await storage.write(
            key: 'tokenExpiry', value: expiryUtc.toIso8601String());
        if (_disposed) return;
        _authToken = authToken;
        _tokenExpiry = expiryUtc;
        _isLoggedIn = true;
        _notifyIfActive();
      });

  // Leave the committed in-memory session intact if either deletion fails.
  // Evaluate ownership at execution time, not when this operation is queued.
  // The condition must be synchronous and must not mutate authentication.
  Future<bool> logOut({bool Function()? ifOwned}) async {
    var loggedOut = false;
    await _enqueue(() async {
      if (ifOwned != null && !ifOwned()) return;
      await storage.delete(key: 'authToken');
      await storage.delete(key: 'tokenExpiry');
      if (_disposed) return;
      _authToken = null;
      _tokenExpiry = null;
      _isLoggedIn = false;
      loggedOut = true;
      _notifyIfActive();
    });
    return loggedOut;
  }

  // Decode JWT to extract user ID
  String? getUserIdFromToken() {
    if (_authToken == null) return null;
    try {
      final parts = _authToken!.split('.');
      if (parts.length != 3) return null;

      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payloadMap = json.decode(payload) as Map<String, dynamic>;

      return payloadMap['id']?.toString();
    } catch (e) {
      return null;
    }
  }

  // Check if token is expired
  bool isTokenExpired() {
    if (_tokenExpiry == null) {
      return true;
    }
    final now = DateTime.now().toUtc();
    final expiryUtc = _tokenExpiry!.toUtc();

    return now.isAfter(expiryUtc);
  }

  // Handle authentication status and redirect if needed
  void handleAuthentication(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadStoredAuthData();
      if (_authToken == null) {
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => CreditsTrackerInfo()),
          );
        }
      } else if (isTokenExpired()) {
        await logOut();
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Login()),
          );
        }
      }
    });
  }
}
