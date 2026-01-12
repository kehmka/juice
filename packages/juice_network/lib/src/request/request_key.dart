import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Unique identity for a request, used for coalescing and caching.
///
/// Two requests with the same [canonical] key are considered identical
/// and will share the same network call and cache entry.
///
/// The key is computed from:
/// - HTTP method
/// - Canonical URL (sorted query params)
/// - Body hash (for POST/PUT/PATCH)
/// - Identity headers hash
/// - Auth scope (optional)
/// - Variant namespace (optional)
@immutable
class RequestKey {
  /// HTTP method (uppercase).
  final String method;

  /// Full URL with query parameters.
  final String url;

  /// Normalized path without query string.
  final String path;

  /// Sorted, normalized query parameters.
  final String? queryString;

  /// Hash of the request body (for POST/PUT/PATCH).
  final String? bodyHash;

  /// Hash of identity-affecting headers.
  final String? headerVaryHash;

  /// Auth scope identifier (e.g., "bearer:user123").
  final String? authScope;

  /// Optional namespace for multi-tenant scenarios.
  final String? variant;

  /// The canonical string representation used for comparison.
  final String canonical;

  const RequestKey._({
    required this.method,
    required this.url,
    required this.path,
    this.queryString,
    this.bodyHash,
    this.headerVaryHash,
    this.authScope,
    this.variant,
    required this.canonical,
  });

  /// Create a RequestKey from request parameters.
  ///
  /// The key is computed deterministically so identical requests
  /// produce identical keys regardless of parameter order.
  factory RequestKey.from({
    required String method,
    required String url,
    Object? body,
    Map<String, String>? headers,
    String? authScope,
    String? variant,
  }) {
    final upperMethod = method.toUpperCase();
    final uri = Uri.parse(url);

    // Normalize path
    final path = _normalizePath(uri.path);

    // Normalize and sort query parameters
    final queryString = _normalizeQueryParams(uri.queryParametersAll);

    // Compute body hash for methods with body
    String? bodyHash;
    if (body != null && _methodHasBody(upperMethod)) {
      bodyHash = _hashBody(body);
    }

    // Compute header vary hash (only identity-affecting headers)
    final headerVaryHash = _hashIdentityHeaders(headers);

    // Build canonical string
    final canonical = _buildCanonical(
      method: upperMethod,
      path: path,
      queryString: queryString,
      bodyHash: bodyHash,
      headerVaryHash: headerVaryHash,
      authScope: authScope,
      variant: variant,
    );

    return RequestKey._(
      method: upperMethod,
      url: url,
      path: path,
      queryString: queryString,
      bodyHash: bodyHash,
      headerVaryHash: headerVaryHash,
      authScope: authScope,
      variant: variant,
      canonical: canonical,
    );
  }

  /// Normalize path: lowercase, remove trailing slash, collapse double slashes.
  static String _normalizePath(String path) {
    var normalized = path.toLowerCase();

    // Remove trailing slash (except for root)
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    // Collapse double slashes
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');

    // Ensure starts with /
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }

    return normalized;
  }

  /// Normalize and sort query parameters.
  ///
  /// - Keys are lowercased
  /// - Keys are sorted alphabetically
  /// - Multiple values for same key are sorted
  static String? _normalizeQueryParams(Map<String, List<String>> params) {
    if (params.isEmpty) return null;

    final normalized = <String>[];

    // Get sorted keys
    final sortedKeys = params.keys.toList()..sort();

    for (final key in sortedKeys) {
      final values = params[key]!;
      // Sort values for same key
      final sortedValues = values.toList()..sort();

      for (final value in sortedValues) {
        // URL encode both key and value
        final encodedKey = Uri.encodeQueryComponent(key.toLowerCase());
        final encodedValue = Uri.encodeQueryComponent(value);
        normalized.add('$encodedKey=$encodedValue');
      }
    }

    return normalized.join('&');
  }

  /// Check if HTTP method typically has a body.
  static bool _methodHasBody(String method) {
    return method == 'POST' || method == 'PUT' || method == 'PATCH';
  }

  /// Hash the request body.
  ///
  /// For JSON bodies, keys are sorted before hashing to ensure
  /// `{"a":1,"b":2}` and `{"b":2,"a":1}` produce the same hash.
  static String _hashBody(Object body) {
    String jsonString;

    if (body is String) {
      // Try to parse as JSON and re-serialize sorted
      try {
        final parsed = jsonDecode(body);
        jsonString = _sortedJsonEncode(parsed);
      } catch (_) {
        // Not valid JSON, hash as-is
        jsonString = body;
      }
    } else if (body is Map || body is List) {
      jsonString = _sortedJsonEncode(body);
    } else {
      jsonString = body.toString();
    }

    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Encode JSON with sorted keys for deterministic output.
  static String _sortedJsonEncode(dynamic value) {
    if (value is Map) {
      final sortedMap = <String, dynamic>{};
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      for (final key in sortedKeys) {
        sortedMap[key] = _sortedJsonEncode(value[key]);
      }
      return jsonEncode(sortedMap);
    } else if (value is List) {
      final sortedList = value.map(_sortedJsonEncode).toList();
      return jsonEncode(sortedList);
    } else {
      return jsonEncode(value);
    }
  }

  /// Headers that affect response identity.
  static const _identityHeaders = [
    'accept',
    'content-type',
    'x-api-version',
    'accept-language',
  ];

  /// Hash only headers that affect response identity.
  ///
  /// NOT included: User-Agent, Cookie, Cache-Control, Authorization
  /// (Authorization is handled via authScope).
  static String? _hashIdentityHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return null;

    final normalized = <String>[];

    for (final name in _identityHeaders) {
      // Check both original case and lowercase
      final value = headers[name] ?? headers[name.toLowerCase()];
      if (value != null && value.isNotEmpty) {
        normalized.add('${name.toLowerCase()}=${value.trim().toLowerCase()}');
      }
    }

    if (normalized.isEmpty) return null;

    normalized.sort();
    final bytes = utf8.encode(normalized.join('&'));
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Build the canonical string representation.
  static String _buildCanonical({
    required String method,
    required String path,
    String? queryString,
    String? bodyHash,
    String? headerVaryHash,
    String? authScope,
    String? variant,
  }) {
    final parts = <String>[method, path];

    if (queryString != null) {
      parts.add('?$queryString');
    }

    if (bodyHash != null) {
      parts.add('#$bodyHash');
    }

    if (headerVaryHash != null) {
      parts.add('^$headerVaryHash');
    }

    if (authScope != null) {
      parts.add('@$authScope');
    }

    if (variant != null) {
      parts.add('~$variant');
    }

    return parts.join(':');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RequestKey && other.canonical == canonical;
  }

  @override
  int get hashCode => canonical.hashCode;

  @override
  String toString() => 'RequestKey($canonical)';
}
