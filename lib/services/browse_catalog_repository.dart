import 'dart:convert';

import 'package:http/http.dart' as http;

/// Short-lived transport responses only; browse parsing stays with each caller.
class BrowseCatalogRepository {
  BrowseCatalogRepository({http.Client? client, DateTime Function()? clock})
      : _client = client,
        _clock = clock ?? DateTime.now;

  static final shared = BrowseCatalogRepository();
  static const ttl = Duration(seconds: 60);
  static const maxEntries = 8;
  static const requestTimeout = Duration(seconds: 25);

  final http.Client? _client;
  final DateTime Function() _clock;
  final Map<Uri, (String, DateTime)> _cache = {};
  final Map<Uri, _Request> _pending = {};

  /// Invalidates pending ownership too, so late responses cannot refill cache.
  void clear() {
    _cache.clear();
    _pending.clear();
  }

  Future<String> fetchListBody(
    Uri uri, {
    bool forceRefresh = false,
    Map<String, String> headers = const {
      'Content-Type': 'application/json; charset=utf-8',
    },
  }) {
    if (forceRefresh) {
      _cache.remove(uri);
    } else {
      final cached = _cache[uri];
      if (cached != null && _clock().difference(cached.$2) < ttl) {
        return Future.value(cached.$1);
      }
      _cache.remove(uri);
      final pending = _pending[uri];
      if (pending != null) return pending.future;
    }

    final request = _Request();
    _pending[uri] = request;
    request.future = _fetch(uri, headers, request);
    return request.future;
  }

  Future<String> _fetch(
      Uri uri, Map<String, String> headers, _Request request) async {
    try {
      final response = await (_client?.get(uri, headers: headers) ??
              http.get(uri, headers: headers))
          .timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw StateError(
            'Catalog request failed (HTTP ${response.statusCode}).');
      }
      final body = response.body;
      if (jsonDecode(body) is! List) {
        throw const FormatException('Unexpected catalog response.');
      }
      if (identical(_pending[uri], request)) {
        _cache.removeWhere((_, entry) => _clock().difference(entry.$2) >= ttl);
        _cache.remove(uri);
        _cache[uri] = (body, _clock());
        while (_cache.length > maxEntries) {
          _cache.remove(_cache.keys.first);
        }
      }
      return body;
    } finally {
      if (identical(_pending[uri], request)) _pending.remove(uri);
    }
  }
}

class _Request {
  late final Future<String> future;
}
