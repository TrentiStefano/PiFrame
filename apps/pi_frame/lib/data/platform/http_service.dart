import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// HTTP requests made by features. Each call may carry a timeout.
abstract class HttpService {
  Future<http.Response> get(Uri uri, {Map<String, String>? headers, Duration? timeout});

  Future<http.Response> post(Uri uri, {Map<String, String>? headers, Object? body, Duration? timeout});

  void close();
}

class PackageHttpService implements HttpService {
  final http.Client _client;

  PackageHttpService({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers, Duration? timeout}) {
    return _withTimeout(_client.get(uri, headers: headers), timeout);
  }

  @override
  Future<http.Response> post(Uri uri, {Map<String, String>? headers, Object? body, Duration? timeout}) {
    return _withTimeout(_client.post(uri, headers: headers, body: body), timeout);
  }

  Future<http.Response> _withTimeout(Future<http.Response> request, Duration? timeout) {
    return timeout == null ? request : request.timeout(timeout);
  }

  @override
  void close() => _client.close();
}

final httpServiceProvider = Provider<HttpService>((ref) {
  final service = PackageHttpService();
  ref.onDispose(service.close);
  return service;
});
