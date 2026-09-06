import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart' as mongo;

import 'sync_models.dart';

class CloudSyncService {
  static const int payloadVersion = 7;
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'KOINLY_SYNC_API_BASE_URL',
    defaultValue: '',
  );

  static String get configuredApiBaseUrl => resolveApiBaseUrl(defaultApiBaseUrl);

  static String normalizeSyncId(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '-').replaceAll(RegExp(r'-+'), '-');
  }

  static String normalizeApiBaseUrl(String value) {
    var normalized = value.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String validateApiBaseUrl(String value) {
    final normalized = normalizeApiBaseUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('Enter a valid HTTPS Worker URL without a path, query, or fragment.');
    }
    return normalized;
  }

  static String resolveApiBaseUrl([String? savedValue]) {
    final provided = normalizeApiBaseUrl(savedValue ?? '');
    if (provided.isNotEmpty) return provided;
    return normalizeApiBaseUrl(defaultApiBaseUrl);
  }

  static Future<void> upload({
    required String apiBaseUrl,
    required String syncId,
    required String pin,
    required Map<String, dynamic> payload,
  }) async {
    await _post(
      apiBaseUrl: apiBaseUrl,
      path: '/api/sync/push',
      body: {
        'syncId': normalizeSyncId(syncId),
        'pin': pin.trim(),
        'payload': payload,
        'deviceId': Platform.localHostname,
        'clientUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  static Future<Map<String, dynamic>> download({
    required String apiBaseUrl,
    required String syncId,
    required String pin,
  }) async {
    final data = await _post(
      apiBaseUrl: apiBaseUrl,
      path: '/api/sync/pull',
      body: {
        'syncId': normalizeSyncId(syncId),
        'pin': pin.trim(),
        'deviceId': Platform.localHostname,
      },
    );
    final payload = data['payload'];
    if (payload is! Map) {
      throw StateError('Cloud data is missing or damaged.');
    }
    return payload.cast<String, dynamic>();
  }

  static Future<void> testBackend(String apiBaseUrl) async {
    final baseUrl = resolveApiBaseUrl(apiBaseUrl);
    if (baseUrl.isEmpty || baseUrl.contains('your-koinly-sync-worker')) {
      throw StateError('Add the Worker API URL first.');
    }
    final response = await http
        .get(
          Uri.parse(baseUrl),
          headers: const {'accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode >= 500) {
      throw StateError('Sync backend is reachable but returned a server error.');
    }
  }

  static Future<Map<String, dynamic>> _post({
    required String apiBaseUrl,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final baseUrl = resolveApiBaseUrl(apiBaseUrl);
    if (baseUrl.isEmpty || baseUrl.contains('your-koinly-sync-worker')) {
      throw StateError('Cloud sync backend URL is not configured in this APK. Rebuild with --dart-define=KOINLY_SYNC_API_BASE_URL=https://your-worker.workers.dev.');
    }
    final uri = Uri.parse('$baseUrl$path');
    final response = await http
        .post(
          uri,
          headers: const {
            'content-type': 'application/json',
            'accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));

    final decoded = response.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final data = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSyncException(
        data['error']?.toString() ?? 'Sync request failed (${response.statusCode}).',
        code: data['code']?.toString(),
      );
    }
    return data;
  }
}

class KoinlySyncApi {
  KoinlySyncApi({required this.baseUrl});

  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('${CloudSyncService.normalizeApiBaseUrl(baseUrl)}$path').replace(queryParameters: query);

  Future<void> validateBackend({bool requireFirstUserRegistration = false}) async {
    final validatedBaseUrl = CloudSyncService.validateApiBaseUrl(baseUrl);
    try {
      final response = await http
          .get(
            Uri.parse('$validatedBaseUrl/health'),
            headers: const {'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 20));
      final decoded = response.body.trim().isEmpty ? null : jsonDecode(response.body);
      final data = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
      if (data['service'] != 'koinly-sync') {
        throw const CloudSyncException('This URL is not a Koinly sync Worker.');
      }
      if (data['configured'] != true) {
        throw const CloudSyncException('The Worker is missing required secrets.');
      }
      if (data['databaseReachable'] != true) {
        throw const CloudSyncException('The Worker cannot connect to its Turso database.');
      }
      if (data['schemaReady'] != true || data['ok'] != true || response.statusCode < 200 || response.statusCode >= 300) {
        throw const CloudSyncException('The Worker is reachable, but its Turso schema is not ready.');
      }
      if (requireFirstUserRegistration && data['registrationMode'] != 'first-user') {
        throw const CloudSyncException('This Worker has managed registration keys enabled. Use a self-hosted Worker configured for first-owner registration.');
      }
    } on TimeoutException {
      throw const CloudSyncException('Worker validation timed out. Check the URL and try again.');
    } on SocketException {
      throw const CloudSyncException('The Worker could not be reached. Check the URL and network.');
    } on http.ClientException {
      throw const CloudSyncException('The Worker could not be reached. Check the URL and network.');
    } on FormatException {
      throw const CloudSyncException('The Worker returned an invalid health response.');
    }
  }

  Future<SyncAuthSession> register({
    required String email,
    required String password,
    required String registrationKey,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    final data = await _post('/v1/auth/register', buildRegistrationPayload(
      email: email,
      password: password,
      registrationKey: registrationKey,
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
    ));
    return _sessionFromResponse(data, email);
  }

  static Map<String, dynamic> buildRegistrationPayload({
    required String email,
    required String password,
    required String registrationKey,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) {
    final normalizedRegistrationKey = registrationKey.trim();
    return {
      'email': email,
      'password': password,
      if (normalizedRegistrationKey.isNotEmpty) 'registrationKey': normalizedRegistrationKey,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
    };
  }

  Future<SyncAuthSession> login({
    required String email,
    required String password,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    final data = await _post('/v1/auth/login', {
      'email': email,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
    });
    return _sessionFromResponse(data, email);
  }

  Future<SyncAuthSession> refresh({required String refreshToken, required String deviceId, required String email}) async {
    final data = await _post('/v1/auth/refresh', {'refreshToken': refreshToken, 'deviceId': deviceId});
    return _sessionFromResponse(data, email);
  }

  Future<void> logout({required String accessToken, required String refreshToken}) async {
    await _post('/v1/auth/logout', {'refreshToken': refreshToken}, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> push({required String accessToken, required List<Map<String, dynamic>> operations}) {
    return _post('/v1/sync/push', {'operations': operations}, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> replaceAll({required String accessToken, required List<Map<String, dynamic>> operations}) {
    return _post('/v1/sync/replace', {'operations': operations}, accessToken: accessToken, timeout: const Duration(minutes: 2));
  }

  Future<Map<String, dynamic>> pull({required String accessToken, required int cursor, int limit = 100}) {
    return _get('/v1/sync/pull', accessToken: accessToken, query: {'cursor': '$cursor', 'limit': '$limit'});
  }

  Future<Map<String, dynamic>> status({required String accessToken}) {
    return _get('/v1/sync/status', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> _get(String path, {String? accessToken, Map<String, String>? query}) async {
    try {
      final response = await http
          .get(
            _uri(path, query),
            headers: {
              'accept': 'application/json',
              if (accessToken != null && accessToken.isNotEmpty) 'authorization': 'Bearer $accessToken',
            },
          )
          .timeout(const Duration(seconds: 25));
      return _decodeResponse(response);
    } on TimeoutException {
      throw const CloudSyncException('Sync request timed out. Check your connection and try again.');
    } on SocketException {
      throw const CloudSyncException('No internet connection. Check your network and try again.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await http
          .post(
            _uri(path),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              if (accessToken != null && accessToken.isNotEmpty) 'authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _decodeResponse(response);
    } on TimeoutException {
      throw const CloudSyncException('Upload timed out. Keep Koinly open on a stronger connection and try again.');
    } on SocketException {
      throw const CloudSyncException('No internet connection. Check your network and try again.');
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> data = <String, dynamic>{};
    final rawBody = response.body.trim();
    if (rawBody.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBody);
        data = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
      } catch (_) {
        final compactBody = rawBody.replaceAll(RegExp(r'\s+'), ' ');
        data = <String, dynamic>{'error': compactBody.length <= 240 ? compactBody : compactBody.substring(0, 240)};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSyncException(data['error']?.toString() ?? 'Request failed (${response.statusCode}).');
    }
    return data;
  }

  SyncAuthSession _sessionFromResponse(Map<String, dynamic> data, String fallbackEmail) {
    final user = (data['user'] as Map? ?? {}).cast<String, dynamic>();
    return SyncAuthSession(
      accessToken: data['accessToken']?.toString() ?? '',
      refreshToken: data['refreshToken']?.toString() ?? '',
      email: user['email']?.toString() ?? fallbackEmail,
      userId: user['id']?.toString() ?? '',
      deviceId: data['deviceId']?.toString() ?? '',
      accessExpiresAt: DateTime.fromMillisecondsSinceEpoch((data['accessExpiresAt'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt()),
    );
  }
}

class MongoDbSyncService {
  static const String defaultDatabaseName = 'koinly';
  static const String defaultCollectionName = 'koinly_sync_snapshots';
  static const String snapshotDocumentId = 'koinly_latest_snapshot';

  static String normalizeDatabaseName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return defaultDatabaseName;
    return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  }

  static String normalizeCollectionName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return defaultCollectionName;
    return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  }

  static Future<void> testConnection({
    required String connectionString,
    required String databaseName,
    required String collectionName,
  }) async {
    final db = await _open(connectionString, databaseName);
    try {
      final collection = db.collection(normalizeCollectionName(collectionName));
      await collection.findOne(mongo.where.eq('_id', '__koinly_connection_test__')).timeout(const Duration(seconds: 20));
    } finally {
      await db.close();
    }
  }

  static Future<void> upload({
    required String connectionString,
    required String databaseName,
    required String collectionName,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _open(connectionString, databaseName);
    try {
      final collection = db.collection(normalizeCollectionName(collectionName));
      final now = DateTime.now().toUtc().toIso8601String();
      await collection.replaceOne(
        mongo.where.eq('_id', snapshotDocumentId),
        <String, dynamic>{
          '_id': snapshotDocumentId,
          'payloadVersion': CloudSyncService.payloadVersion,
          'payload': payload,
          'deviceId': Platform.localHostname,
          'updatedAt': now,
        },
        upsert: true,
      ).timeout(const Duration(seconds: 28));
    } finally {
      await db.close();
    }
  }

  static Future<Map<String, dynamic>> download({
    required String connectionString,
    required String databaseName,
    required String collectionName,
  }) async {
    final db = await _open(connectionString, databaseName);
    try {
      final collection = db.collection(normalizeCollectionName(collectionName));
      final document = await collection.findOne(mongo.where.eq('_id', snapshotDocumentId)).timeout(const Duration(seconds: 28));
      if (document == null) {
        throw StateError('No MongoDB sync snapshot exists yet. Upload local data first.');
      }
      final payload = document['payload'];
      if (payload is! Map) {
        throw StateError('MongoDB sync data is missing or damaged.');
      }
      final normalizedPayload = _normalizeBsonValue(payload);
      if (normalizedPayload is! Map) {
        throw StateError('MongoDB sync data is missing or damaged.');
      }
      return normalizedPayload.cast<String, dynamic>();
    } finally {
      await db.close();
    }
  }

  static dynamic _normalizeBsonValue(dynamic value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is List) {
      return value.map(_normalizeBsonValue).toList();
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _normalizeBsonValue(item)));
    }

    final typeName = value.runtimeType.toString();
    if (typeName == 'Int64' || typeName.endsWith('.Int64')) {
      return int.tryParse(value.toString()) ?? double.tryParse(value.toString()) ?? value.toString();
    }
    return value.toString();
  }

  static Future<mongo.Db> _open(String connectionString, String databaseName) async {
    final normalized = connectionString.trim();
    if (normalized.isEmpty) {
      throw StateError('Add your MongoDB URL first.');
    }
    if (!normalized.startsWith('mongodb://') && !normalized.startsWith('mongodb+srv://')) {
      throw StateError('MongoDB URL must start with mongodb:// or mongodb+srv://.');
    }
    final resolvedUri = _withDatabaseName(normalized, normalizeDatabaseName(databaseName));
    final db = await mongo.Db.create(resolvedUri);
    await db.open().timeout(const Duration(seconds: 22));
    return db;
  }

  static String _withDatabaseName(String uri, String databaseName) {
    final queryIndex = uri.indexOf('?');
    final beforeQuery = queryIndex == -1 ? uri : uri.substring(0, queryIndex);
    final query = queryIndex == -1 ? '' : uri.substring(queryIndex);
    final schemeIndex = beforeQuery.indexOf('://');
    if (schemeIndex == -1) return uri;
    final hostStart = schemeIndex + 3;
    final slashIndex = beforeQuery.indexOf('/', hostStart);
    if (slashIndex == -1) {
      return '$beforeQuery/$databaseName$query';
    }
    final path = beforeQuery.substring(slashIndex + 1).trim();
    if (path.isEmpty) {
      return '${beforeQuery.substring(0, slashIndex)}/$databaseName$query';
    }
    return uri;
  }
}
