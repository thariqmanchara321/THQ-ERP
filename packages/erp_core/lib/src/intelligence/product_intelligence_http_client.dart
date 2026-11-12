import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Abstraction for HTTP operations required by external intelligence providers.
abstract class ProductIntelligenceHttpClient {
  Future<String> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  });
}

/// Default production HTTP client using `dart:io` [HttpClient].
class DefaultProductIntelligenceHttpClient implements ProductIntelligenceHttpClient {
  final HttpClient _client;

  DefaultProductIntelligenceHttpClient({HttpClient? client}) : _client = client ?? HttpClient();

  @override
  Future<String> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _client.connectionTimeout = timeout;

    final request = await _client.getUrl(uri).timeout(
          timeout,
          onTimeout: () => throw TimeoutException('Connection timed out to $uri', timeout),
        );

    // Apply mandatory compliance headers
    request.headers.set('User-Agent', 'THQ-ERP/1.0 (https://thqerp.com; contact@thqerp.com)');
    request.headers.set('Accept', 'application/json');

    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });

    final response = await request.close().timeout(
          timeout,
          onTimeout: () => throw TimeoutException('Response timed out from $uri', timeout),
        );

    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else if (response.statusCode == 404) {
      return '';
    } else if (response.statusCode == 429) {
      throw const HttpException('External provider rate limit exceeded (HTTP 429)');
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw HttpException('External provider authorization required (HTTP ${response.statusCode})');
    } else {
      throw HttpException('External provider returned HTTP ${response.statusCode}: $body');
    }
  }
}

/// In-memory mock HTTP client for hermetic, deterministic testing without live network calls.
class MockProductIntelligenceHttpClient implements ProductIntelligenceHttpClient {
  final Map<String, String> responses = {};
  final Set<String> rateLimitedUrls = {};
  final Set<String> errorUrls = {};
  Duration simulatedDelay = Duration.zero;

  void setMockResponse(Uri uri, {int statusCode = 200, required String body}) {
    final url = uri.toString();
    if (statusCode == 429) {
      rateLimitedUrls.add(url);
    } else if (statusCode >= 400 && statusCode != 404) {
      errorUrls.add(url);
    } else if (statusCode == 404) {
      responses[url] = '';
    } else {
      responses[url] = body;
    }
  }

  @override
  Future<String> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    final urlStr = uri.toString();

    if (rateLimitedUrls.contains(urlStr)) {
      throw const HttpException('External provider rate limit exceeded (HTTP 429)');
    }

    if (errorUrls.contains(urlStr)) {
      throw const HttpException('External provider internal server error (HTTP 500)');
    }

    // Direct match or prefix match
    if (responses.containsKey(urlStr)) {
      return responses[urlStr]!;
    }

    for (final entry in responses.entries) {
      if (urlStr.contains(entry.key)) {
        return entry.value;
      }
    }

    return '';
  }
}
