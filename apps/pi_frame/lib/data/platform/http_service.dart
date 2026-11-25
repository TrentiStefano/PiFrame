import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// What an HTTP request answered. Plain Dart, so features need no HTTP package import.
class HttpResponse {
  final int statusCode;
  final Uint8List bodyBytes;
  final String? reasonPhrase;

  /// The address the answer came from, after redirects.
  final Uri url;

  const HttpResponse({required this.statusCode, required this.bodyBytes, required this.url, this.reasonPhrase});
}

/// HTTP requests made by features. Each call may carry a timeout.
abstract class HttpService {
  Future<HttpResponse> get(Uri uri, {Map<String, String>? headers, Duration? timeout});

  Future<HttpResponse> post(Uri uri, {Map<String, String>? headers, Object? body, Duration? timeout});

  void close();
}

class PackageHttpService implements HttpService {
  final http.Client _client;

  PackageHttpService({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<HttpResponse> get(Uri uri, {Map<String, String>? headers, Duration? timeout}) {
    return _withTimeout(_client.get(uri, headers: headers), uri, timeout);
  }

  @override
  Future<HttpResponse> post(Uri uri, {Map<String, String>? headers, Object? body, Duration? timeout}) {
    return _withTimeout(_client.post(uri, headers: headers, body: body), uri, timeout);
  }

  Future<HttpResponse> _withTimeout(Future<http.Response> request, Uri uri, Duration? timeout) async {
    final response = await (timeout == null ? request : request.timeout(timeout));
    return HttpResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      reasonPhrase: response.reasonPhrase,
      url: response.request?.url ?? uri,
    );
  }

  @override
  void close() => _client.close();
}

final httpServiceProvider = Provider<HttpService>((ref) {
  final service = PackageHttpService();
  ref.onDispose(service.close);
  return service;
});
