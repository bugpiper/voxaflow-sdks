import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors.dart';

/// Thin REST client: attaches the Voxa access token, parses JSON, and on a 401
/// transparently refreshes the token (via the app's onTokenRefresh) and retries once.
class VoxaRest {
  VoxaRest({
    required this.endpoint,
    required String token,
    this.onTokenRefresh,
    this.onTokenChanged,
    http.Client? httpClient,
  })  : _token = token,
        _http = httpClient ?? http.Client();

  /// API base, e.g. `https://api.voxaflow.com/api`.
  final String endpoint;
  final Future<String> Function()? onTokenRefresh;

  /// Called whenever the token is refreshed, so the realtime layer can re-auth.
  /// Mutable so the owning VoxaClient can wire it after constructing both transports.
  void Function(String token)? onTokenChanged;

  final http.Client _http;
  String _token;

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body);

  Future<Map<String, dynamic>> get(String path) => _send('GET', path, null);

  Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) =>
      _send('PUT', path, body);

  Future<Map<String, dynamic>> delete(String path, [Map<String, dynamic>? body]) =>
      _send('DELETE', path, body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    bool retry = true,
  }) async {
    final uri = Uri.parse('$endpoint$path');
    http.Response res;
    try {
      final req = http.Request(method, uri)
        ..headers['authorization'] = 'Bearer $_token';
      // Only declare a JSON content-type when there's actually a body — Fastify
      // rejects an empty body sent with content-type: application/json (HTTP 400).
      if (body != null) {
        req.headers['content-type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      res = await http.Response.fromStream(await _http.send(req));
    } catch (e) {
      throw VoxaError(VoxaErrorCode.connection, 'Network error calling $path', cause: e);
    }

    // Transparent refresh on auth failure.
    if (res.statusCode == 401 && retry && onTokenRefresh != null) {
      try {
        _token = await onTokenRefresh!();
        onTokenChanged?.call(_token);
      } catch (e) {
        throw VoxaError(VoxaErrorCode.auth, 'Token refresh failed', cause: e, status: 401);
      }
      return _send(method, path, body, retry: false);
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return const {};
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw VoxaError(VoxaErrorCode.auth, _errMsg(res), status: res.statusCode);
    }
    throw VoxaError(VoxaErrorCode.server, _errMsg(res), status: res.statusCode);
  }

  String _errMsg(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      if (j is Map && (j['message'] != null || j['error'] != null)) {
        return (j['message'] ?? j['error']).toString();
      }
    } catch (_) {}
    return 'Request failed (HTTP ${res.statusCode})';
  }

  void close() => _http.close();
}
