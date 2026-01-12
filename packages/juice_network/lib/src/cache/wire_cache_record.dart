import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A cached HTTP response stored as raw wire data.
///
/// CRITICAL: Cache stores raw response bytes, NOT decoded types.
/// This prevents:
/// - Decoder bugs from corrupting cache
/// - Type T from fragmenting cache (same URL, different decoders = same entry)
/// - Serialization issues with complex types
@immutable
class WireCacheRecord {
  /// The canonical request key this caches.
  final String canonicalKey;

  /// Raw response body bytes.
  final Uint8List bodyBytes;

  /// HTTP status code.
  final int statusCode;

  /// Response headers (subset: content-type, etag, last-modified, cache-control).
  final Map<String, String> headers;

  /// When this was cached.
  final DateTime cachedAt;

  /// When this expires (computed from TTL or Cache-Control).
  final DateTime? expiresAt;

  /// ETag for conditional requests.
  final String? etag;

  /// Last-Modified for conditional requests.
  final String? lastModified;

  const WireCacheRecord({
    required this.canonicalKey,
    required this.bodyBytes,
    required this.statusCode,
    required this.headers,
    required this.cachedAt,
    this.expiresAt,
    this.etag,
    this.lastModified,
  });

  /// Create from a Dio response.
  factory WireCacheRecord.fromResponse(
    Response<dynamic> response,
    String canonicalKey, {
    Duration? ttl,
  }) {
    // Extract relevant headers
    final headers = <String, String>{};
    final responseHeaders = response.headers.map;

    for (final key in ['content-type', 'etag', 'last-modified', 'cache-control']) {
      final values = responseHeaders[key];
      if (values != null && values.isNotEmpty) {
        headers[key] = values.first;
      }
    }

    // Extract ETag and Last-Modified
    final etag = responseHeaders['etag']?.firstOrNull;
    final lastModified = responseHeaders['last-modified']?.firstOrNull;

    // Compute expiry
    DateTime? expiresAt;
    if (ttl != null) {
      expiresAt = DateTime.now().add(ttl);
    } else {
      // Try to parse from Cache-Control
      expiresAt = _parseMaxAge(responseHeaders['cache-control']?.firstOrNull);
    }

    // Convert body to bytes
    Uint8List bodyBytes;
    final data = response.data;
    if (data is Uint8List) {
      bodyBytes = data;
    } else if (data is List<int>) {
      bodyBytes = Uint8List.fromList(data);
    } else if (data is String) {
      bodyBytes = Uint8List.fromList(utf8.encode(data));
    } else if (data != null) {
      // JSON encode other types
      bodyBytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    } else {
      bodyBytes = Uint8List(0);
    }

    return WireCacheRecord(
      canonicalKey: canonicalKey,
      bodyBytes: bodyBytes,
      statusCode: response.statusCode ?? 200,
      headers: headers,
      cachedAt: DateTime.now(),
      expiresAt: expiresAt,
      etag: etag,
      lastModified: lastModified,
    );
  }

  /// Parse max-age from Cache-Control header.
  static DateTime? _parseMaxAge(String? cacheControl) {
    if (cacheControl == null) return null;

    final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
    if (match != null) {
      final seconds = int.tryParse(match.group(1)!);
      if (seconds != null) {
        return DateTime.now().add(Duration(seconds: seconds));
      }
    }
    return null;
  }

  /// Size in bytes for cache eviction calculations.
  int get sizeBytes => bodyBytes.length;

  /// Check if expired.
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Check if stale (same as expired, but usable for stale-while-revalidate).
  bool get isStale => isExpired;

  /// Check if response should never be cached based on headers.
  bool get hasNoStore {
    final cacheControl = headers['cache-control'];
    return cacheControl != null && cacheControl.contains('no-store');
  }

  /// Check if response should always be revalidated.
  bool get hasNoCache {
    final cacheControl = headers['cache-control'];
    return cacheControl != null && cacheControl.contains('no-cache');
  }

  /// Age of this cache entry.
  Duration get age => DateTime.now().difference(cachedAt);

  /// Time until expiry (negative if expired).
  Duration? get timeToLive {
    if (expiresAt == null) return null;
    return expiresAt!.difference(DateTime.now());
  }

  /// Decode the body as a UTF-8 string.
  String get bodyString => utf8.decode(bodyBytes);

  /// Decode the body as JSON.
  dynamic get bodyJson => jsonDecode(bodyString);

  /// Serialize to bytes for storage.
  Uint8List toBytes() {
    final map = {
      'canonicalKey': canonicalKey,
      'bodyBytes': base64Encode(bodyBytes),
      'statusCode': statusCode,
      'headers': headers,
      'cachedAt': cachedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'etag': etag,
      'lastModified': lastModified,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Deserialize from bytes.
  factory WireCacheRecord.fromBytes(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return WireCacheRecord(
      canonicalKey: map['canonicalKey'] as String,
      bodyBytes: base64Decode(map['bodyBytes'] as String),
      statusCode: map['statusCode'] as int,
      headers: Map<String, String>.from(map['headers'] as Map),
      cachedAt: DateTime.parse(map['cachedAt'] as String),
      expiresAt: map['expiresAt'] != null
          ? DateTime.parse(map['expiresAt'] as String)
          : null,
      etag: map['etag'] as String?,
      lastModified: map['lastModified'] as String?,
    );
  }

  /// Create a copy with updated expiry.
  WireCacheRecord copyWithExpiry(DateTime? expiresAt) {
    return WireCacheRecord(
      canonicalKey: canonicalKey,
      bodyBytes: bodyBytes,
      statusCode: statusCode,
      headers: headers,
      cachedAt: cachedAt,
      expiresAt: expiresAt,
      etag: etag,
      lastModified: lastModified,
    );
  }

  /// Refresh the cached timestamp (for 304 responses).
  WireCacheRecord touch({Duration? ttl}) {
    return WireCacheRecord(
      canonicalKey: canonicalKey,
      bodyBytes: bodyBytes,
      statusCode: statusCode,
      headers: headers,
      cachedAt: DateTime.now(),
      expiresAt: ttl != null ? DateTime.now().add(ttl) : expiresAt,
      etag: etag,
      lastModified: lastModified,
    );
  }

  @override
  String toString() =>
      'WireCacheRecord($canonicalKey, ${sizeBytes}b, expired: $isExpired)';
}
