import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class WorkerDeploymentConfig {
  const WorkerDeploymentConfig({
    required this.workerName,
    required this.cloudflareAccountId,
    required this.cloudflareApiToken,
    required this.tursoDatabaseUrl,
    required this.tursoAuthToken,
    required this.jwtSecret,
    required this.adminUsername,
    required this.adminPassword,
  });

  final String workerName;
  final String cloudflareAccountId;
  final String cloudflareApiToken;
  final String tursoDatabaseUrl;
  final String tursoAuthToken;
  final String jwtSecret;
  final String adminUsername;
  final String adminPassword;
}

class WorkerDeploymentResult {
  const WorkerDeploymentResult({required this.workerUrl});
  final String workerUrl;
}

class WorkerDeploymentException implements Exception {
  const WorkerDeploymentException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef WorkerDeploymentProgress = void Function(String message);

class WorkerDeploymentService {
  WorkerDeploymentService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _cloudflareApi = 'https://api.cloudflare.com/client/v4';
  static const _bundleAsset = 'assets/worker/koinly_sync_worker.js';
  static const _schemaAsset = 'cloud/worker/schema.sql';

  void close() => _client.close();

  Future<WorkerDeploymentResult> deploy(
    WorkerDeploymentConfig raw, {
    required WorkerDeploymentProgress onProgress,
  }) async {
    final config = _normalized(raw);
    _validate(config);

    onProgress('Checking Cloudflare credentials…');
    final accountSubdomain = await _cloudflareAccountSubdomain(config);

    onProgress('Checking Turso database…');
    await _checkTurso(config);

    onProgress('Preparing database schema…');
    await _applySchema(config);

    onProgress('Preparing secure administrator credentials…');
    final passwordHash = await compute(_pbkdf2PasswordHash, config.adminPassword);

    onProgress('Preparing Worker runtime…');
    final lifecycle = await _durableObjectLifecycleMetadata(config);

    onProgress('Uploading Koinly Sync Worker…');
    final bundle = await _loadWorkerBundle();
    await _uploadWorker(config, bundle, passwordHash, lifecycle);

    onProgress('Enabling workers.dev URL…');
    await _enableWorkerSubdomain(config);

    onProgress('Configuring automatic backup scheduler…');
    await _configureCron(config);

    final workerUrl = 'https://${config.workerName}.$accountSubdomain.workers.dev';
    onProgress('Waiting for Worker health check…');
    await _waitForHealthyWorker(workerUrl);

    onProgress('Worker deployed successfully.');
    return WorkerDeploymentResult(workerUrl: workerUrl);
  }

  WorkerDeploymentConfig _normalized(WorkerDeploymentConfig c) => WorkerDeploymentConfig(
        workerName: c.workerName.trim().toLowerCase(),
        cloudflareAccountId: c.cloudflareAccountId.trim(),
        cloudflareApiToken: c.cloudflareApiToken.trim(),
        tursoDatabaseUrl: c.tursoDatabaseUrl.trim(),
        tursoAuthToken: c.tursoAuthToken.trim(),
        jwtSecret: c.jwtSecret.trim(),
        adminUsername: c.adminUsername.trim().toLowerCase(),
        adminPassword: c.adminPassword,
      );

  void _validate(WorkerDeploymentConfig c) {
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(c.workerName)) {
      throw const WorkerDeploymentException('Worker name must be 1–63 lowercase letters, numbers, or dashes and cannot start or end with a dash.');
    }
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(c.cloudflareAccountId)) {
      throw const WorkerDeploymentException('Cloudflare Account ID must be the 32-character Account ID from the Cloudflare dashboard.');
    }
    if (c.cloudflareApiToken.isEmpty) throw const WorkerDeploymentException('Enter a Cloudflare API token.');
    if (!RegExp(r'^libsql://[^/?\s]+\.turso\.io/?$').hasMatch(c.tursoDatabaseUrl)) {
      throw const WorkerDeploymentException('Turso Database URL must use libsql://…turso.io.');
    }
    if (c.tursoAuthToken.isEmpty) throw const WorkerDeploymentException('Enter the Turso database auth token.');
    if (c.jwtSecret.length < 32) throw const WorkerDeploymentException('JWT secret must contain at least 32 characters.');
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$').hasMatch(c.adminUsername)) {
      throw const WorkerDeploymentException('Administrator username must be 3–32 lowercase letters, numbers, dots, dashes, or underscores.');
    }
    if (c.adminPassword.length < 12 || c.adminPassword.length > 256) {
      throw const WorkerDeploymentException('Administrator password must contain 12–256 characters.');
    }
  }

  Map<String, String> _cfHeaders(WorkerDeploymentConfig c) => {
        'authorization': 'Bearer ${c.cloudflareApiToken}',
        'accept': 'application/json',
      };

  Future<String> _cloudflareAccountSubdomain(WorkerDeploymentConfig c) async {
    final uri = Uri.parse('$_cloudflareApi/accounts/${c.cloudflareAccountId}/workers/subdomain');
    final response = await _client.get(uri, headers: _cfHeaders(c)).timeout(const Duration(seconds: 30));
    final data = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
      throw WorkerDeploymentException('Cloudflare authentication failed: ${_cloudflareError(data, response.statusCode)}');
    }
    final result = data['result'];
    final subdomain = result is Map ? '${result['subdomain'] ?? ''}'.trim() : '';
    if (subdomain.isEmpty) {
      throw const WorkerDeploymentException('Your Cloudflare account does not have a workers.dev subdomain yet. Open Workers & Pages once in Cloudflare, create/confirm the account subdomain, then retry.');
    }
    return subdomain;
  }

  String _tursoHttpBase(String libsqlUrl) => libsqlUrl.replaceFirst(RegExp(r'^libsql://'), 'https://').replaceFirst(RegExp(r'/$'), '');

  Future<void> _checkTurso(WorkerDeploymentConfig c) async {
    final response = await _client.get(
      Uri.parse('${_tursoHttpBase(c.tursoDatabaseUrl)}/version'),
      headers: {'authorization': 'Bearer ${c.tursoAuthToken}'},
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkerDeploymentException('Could not authenticate with the Turso database (HTTP ${response.statusCode}). Check the database URL and database auth token.');
    }
  }

  Future<void> _applySchema(WorkerDeploymentConfig c) async {
    final sql = await rootBundle.loadString(_schemaAsset);
    final statements = _splitSqlStatements(sql);
    if (statements.isEmpty) throw const WorkerDeploymentException('Koinly database schema is missing from this build.');

    // Apply idempotent CREATE/INDEX statements in small pipelines. Existing
    // installations keep their rows because schema.sql uses IF NOT EXISTS.
    for (var index = 0; index < statements.length; index += 18) {
      final end = min(index + 18, statements.length);
      await _tursoExecuteMany(c, statements.sublist(index, end));
    }

    // Forward migrations for databases created by older Koinly Workers. Keep
    // this in sync with cloud/worker/scripts/apply-schema.mjs so switching
    // between GitHub Actions deployment and in-app deployment is safe.
    await _migrateLegacyUsers(c);
    await _migrateAnalyticsUploadSettings(c);
    await _migrateAnalyticsPdfSchedules(c);
  }

  Future<void> _migrateLegacyUsers(WorkerDeploymentConfig c) async {
    var columns = await _tursoColumnNames(c, 'users');
    if (columns.isEmpty) return;
    if (columns.contains('email') && !columns.contains('username')) {
      await _tursoExecuteMany(c, ['ALTER TABLE users RENAME COLUMN email TO username']);
      columns = await _tursoColumnNames(c, 'users');
      final users = await _tursoQuery(c, 'SELECT id, username FROM users');
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in users) {
        final id = '${row['id'] ?? ''}';
        final legacy = '${row['username'] ?? ''}';
        final migrated = _legacyUsername(legacy);
        if (id.isNotEmpty && migrated != legacy) {
          await _tursoExecuteMany(c, [
            'UPDATE users SET username = ${_sqlText(migrated)}, updated_at = $now WHERE id = ${_sqlText(id)}',
          ]);
        }
      }
    }
    columns = await _tursoColumnNames(c, 'users');
    final migrations = <String>[];
    if (!columns.contains('recovery_key_hash')) {
      migrations.add('ALTER TABLE users ADD COLUMN recovery_key_hash TEXT');
    }
    if (!columns.contains('session_version')) {
      migrations.add('ALTER TABLE users ADD COLUMN session_version INTEGER NOT NULL DEFAULT 0');
    }
    if (migrations.isNotEmpty) await _tursoExecuteMany(c, migrations);
  }

  Future<void> _migrateAnalyticsUploadSettings(WorkerDeploymentConfig c) async {
    final columns = await _tursoColumnNames(c, 'analytics_upload_settings');
    if (columns.isNotEmpty && !columns.contains('google_folder_id')) {
      await _tursoExecuteMany(c, ["ALTER TABLE analytics_upload_settings ADD COLUMN google_folder_id TEXT NOT NULL DEFAULT ''"]);
    }
  }

  Future<void> _migrateAnalyticsPdfSchedules(WorkerDeploymentConfig c) async {
    final tableRows = await _tursoQuery(
      c,
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'analytics_pdf_schedules'",
    );
    if (tableRows.isEmpty) return;
    final tableSql = '${tableRows.first['sql'] ?? ''}';
    final columns = await _tursoColumnNames(c, 'analytics_pdf_schedules');
    final supportsCustom = tableSql.contains("'custom'") && columns.contains('custom_start') && columns.contains('custom_end');
    final supportsFormats = columns.contains('file_format') && tableSql.contains("'xlsx'") && tableSql.contains("'txt'");
    if (supportsCustom && supportsFormats) return;

    final customStart = columns.contains('custom_start') ? 'custom_start' : 'NULL';
    final customEnd = columns.contains('custom_end') ? 'custom_end' : 'NULL';
    final fileFormat = columns.contains('file_format') ? 'file_format' : "'pdf'";
    await _tursoExecuteMany(c, [
      'BEGIN IMMEDIATE',
      'DROP INDEX IF EXISTS idx_analytics_pdf_schedule_due',
      'DROP TABLE IF EXISTS analytics_pdf_schedules_v1155',
      '''CREATE TABLE analytics_pdf_schedules_v1155 (
        user_id TEXT NOT NULL,
        destination TEXT NOT NULL CHECK(destination IN ('telegram', 'googleDrive')),
        enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
        report_variant TEXT NOT NULL DEFAULT 'summary' CHECK(report_variant IN ('summary', 'transactionHistory')),
        file_format TEXT NOT NULL DEFAULT 'pdf' CHECK(file_format IN ('pdf', 'xlsx', 'txt')),
        date_filter TEXT NOT NULL DEFAULT 'thisMonth' CHECK(date_filter IN ('today', 'thisWeek', 'thisMonth', 'thisYear', 'allTime', 'custom')),
        custom_start TEXT,
        custom_end TEXT,
        frequency TEXT NOT NULL DEFAULT 'daily' CHECK(frequency IN ('daily', 'weekly', 'monthly')),
        hour INTEGER NOT NULL DEFAULT 3 CHECK(hour BETWEEN 0 AND 23),
        minute INTEGER NOT NULL DEFAULT 0 CHECK(minute BETWEEN 0 AND 59),
        weekday INTEGER NOT NULL DEFAULT 7 CHECK(weekday BETWEEN 1 AND 7),
        month_day INTEGER NOT NULL DEFAULT 1 CHECK(month_day BETWEEN 1 AND 31),
        timezone_offset_minutes INTEGER NOT NULL DEFAULT 0 CHECK(timezone_offset_minutes BETWEEN -840 AND 840),
        next_due_at INTEGER,
        last_sent_at INTEGER,
        last_attempt_at INTEGER,
        last_error TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(user_id, destination),
        FOREIGN KEY(user_id) REFERENCES users(id)
      )''',
      '''INSERT INTO analytics_pdf_schedules_v1155(
          user_id, destination, enabled, report_variant, file_format, date_filter, custom_start, custom_end, frequency,
          hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
          last_sent_at, last_attempt_at, last_error, updated_at
        )
        SELECT user_id, destination, enabled, report_variant, $fileFormat, date_filter, $customStart, $customEnd, frequency,
          hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
          last_sent_at, last_attempt_at, last_error, updated_at
        FROM analytics_pdf_schedules''',
      'DROP TABLE analytics_pdf_schedules',
      'ALTER TABLE analytics_pdf_schedules_v1155 RENAME TO analytics_pdf_schedules',
      'CREATE INDEX IF NOT EXISTS idx_analytics_pdf_schedule_due ON analytics_pdf_schedules(enabled, next_due_at)',
      'COMMIT',
    ]);
  }

  String _legacyUsername(String value) {
    final raw = value.trim().toLowerCase();
    final localPart = raw.contains('@') ? raw.split('@').first : raw;
    var username = localPart
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
    if (username.length > 32) username = username.substring(0, 32);
    if (username.isEmpty) username = 'koinly_owner';
    while (username.length < 3) {
      username = '${username}_owner';
      if (username.length > 32) username = username.substring(0, 32);
    }
    username = username.replaceAll(RegExp(r'[._-]+$'), '');
    return username.isEmpty ? 'koinly_owner' : username;
  }

  String _sqlText(String value) => "'${value.replaceAll("'", "''")}'";

  Future<Set<String>> _tursoColumnNames(WorkerDeploymentConfig c, String table) async {
    final result = await _tursoQuery(c, "PRAGMA table_info('$table')");
    return result.map((row) => '${row['name'] ?? ''}').where((value) => value.isNotEmpty).toSet();
  }

  Future<List<Map<String, Object?>>> _tursoQuery(WorkerDeploymentConfig c, String sql) async {
    final data = await _tursoPipeline(c, [sql]);
    if (data.isEmpty) return const [];
    final execute = data.first;
    final colsRaw = execute['cols'];
    final rowsRaw = execute['rows'];
    if (colsRaw is! List || rowsRaw is! List) return const [];
    final names = colsRaw.map((col) => col is Map ? '${col['name'] ?? ''}' : '').toList();
    return rowsRaw.whereType<List>().map((row) {
      final values = <String, Object?>{};
      for (var i = 0; i < row.length && i < names.length; i++) {
        final cell = row[i];
        Object? value;
        if (cell is Map) {
          final type = '${cell['type'] ?? ''}';
          if (type == 'null') {
            value = null;
          } else if (type == 'integer') {
            value = int.tryParse('${cell['value'] ?? ''}') ?? cell['value'];
          } else if (type == 'float') {
            value = double.tryParse('${cell['value'] ?? ''}') ?? cell['value'];
          } else {
            value = cell['value'];
          }
        }
        values[names[i]] = value;
      }
      return values;
    }).toList();
  }

  Future<void> _tursoExecuteMany(WorkerDeploymentConfig c, List<String> statements) async {
    await _tursoPipeline(c, statements);
  }

  Future<List<Map<String, Object?>>> _tursoPipeline(WorkerDeploymentConfig c, List<String> statements) async {
    final requests = <Map<String, Object?>>[
      for (final statement in statements)
        {
          'type': 'execute',
          'stmt': {'sql': statement},
        },
      {'type': 'close'},
    ];
    final response = await _client.post(
      Uri.parse('${_tursoHttpBase(c.tursoDatabaseUrl)}/v2/pipeline'),
      headers: {
        'authorization': 'Bearer ${c.tursoAuthToken}',
        'content-type': 'application/json',
      },
      body: jsonEncode({'requests': requests}),
    ).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkerDeploymentException('Turso schema update failed (HTTP ${response.statusCode}).');
    }
    final body = _decodeJson(response.body);
    final rawResults = body['results'];
    if (rawResults is! List) throw const WorkerDeploymentException('Turso returned an invalid schema response.');
    final outputs = <Map<String, Object?>>[];
    for (final entry in rawResults) {
      if (entry is! Map) continue;
      if (entry['type'] == 'error') {
        final error = entry['error'];
        final message = error is Map ? '${error['message'] ?? 'Database error'}' : 'Database error';
        throw WorkerDeploymentException('Turso schema update failed: $message');
      }
      final responsePart = entry['response'];
      if (responsePart is Map && responsePart['type'] == 'execute') {
        final result = responsePart['result'];
        if (result is Map) outputs.add(Map<String, Object?>.from(result));
      }
    }
    return outputs;
  }

  Future<String> _loadWorkerBundle() async {
    final bundle = await rootBundle.loadString(_bundleAsset);
    if (bundle.contains('KOINLY_WORKER_BUNDLE_PLACEHOLDER') || bundle.trim().length < 10000) {
      throw const WorkerDeploymentException('This app build does not contain the deployable Worker bundle. Install an official Koinly release built by the release workflow and try again.');
    }
    return bundle;
  }

  Future<Map<String, Object?>> _durableObjectLifecycleMetadata(WorkerDeploymentConfig c) async {
    final uri = Uri.parse(
      '$_cloudflareApi/accounts/${c.cloudflareAccountId}/workers/scripts/${Uri.encodeComponent(c.workerName)}/settings',
    );
    final response = await _client.get(uri, headers: _cfHeaders(c)).timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) {
      return const {
        'migrations': {
          'new_tag': 'v1-realtime-sync-hub',
          'new_sqlite_classes': ['SyncHub'],
        },
      };
    }
    final data = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
      throw WorkerDeploymentException('Could not inspect the existing Worker: ${_cloudflareError(data, response.statusCode)}');
    }
    final result = data['result'];
    if (result is Map) {
      // Preserve an exports-managed Worker if an advanced/current Cloudflare
      // deployment has already migrated away from legacy migration tags.
      final exports = result['exports'];
      if (exports is Map && exports['SyncHub'] is Map) {
        final existing = exports['SyncHub'] as Map;
        final storage = '${existing['storage'] ?? 'sqlite'}';
        return {
          'exports': {
            'SyncHub': {'type': 'durable-object', 'storage': storage},
          },
        };
      }
      final migrationTag = '${result['migration_tag'] ?? ''}'.trim();
      final migrations = result['migrations'];
      final configuredTag = migrations is Map ? '${migrations['new_tag'] ?? ''}'.trim() : '';
      if (migrationTag.isNotEmpty || configuredTag.isNotEmpty) return const {};
    }
    return const {
      'migrations': {
        'new_tag': 'v1-realtime-sync-hub',
        'new_sqlite_classes': ['SyncHub'],
      },
    };
  }

  Future<void> _uploadWorker(
    WorkerDeploymentConfig c,
    String bundle,
    String adminPasswordHash,
    Map<String, Object?> lifecycle,
  ) async {
    final uri = Uri.parse('$_cloudflareApi/accounts/${c.cloudflareAccountId}/workers/scripts/${Uri.encodeComponent(c.workerName)}');
    final metadata = <String, Object?>{
      'main_module': 'worker.js',
      'compatibility_date': '2026-08-21',
      'bindings': [
        {'type': 'secret_text', 'name': 'TURSO_DATABASE_URL', 'text': c.tursoDatabaseUrl},
        {'type': 'secret_text', 'name': 'TURSO_AUTH_TOKEN', 'text': c.tursoAuthToken},
        {'type': 'secret_text', 'name': 'JWT_SECRET', 'text': c.jwtSecret},
        {'type': 'secret_text', 'name': 'ADMIN_USERNAME', 'text': c.adminUsername},
        {'type': 'secret_text', 'name': 'ADMIN_PASSWORD_HASH', 'text': adminPasswordHash},
        {'type': 'plain_text', 'name': 'ACCESS_TOKEN_TTL_SECONDS', 'text': '900'},
        {'type': 'plain_text', 'name': 'REFRESH_TOKEN_TTL_SECONDS', 'text': '2592000'},
        {'type': 'plain_text', 'name': 'MAX_SYNC_BATCH_SIZE', 'text': '100'},
        {'type': 'plain_text', 'name': 'MAX_SYNC_REPLACE_SIZE', 'text': '25000'},
        {'type': 'durable_object_namespace', 'name': 'SYNC_HUB', 'class_name': 'SyncHub'},
      ],
      ...lifecycle,
    };

    final request = http.MultipartRequest('PUT', uri)
      ..headers.addAll(_cfHeaders(c))
      ..files.add(http.MultipartFile.fromString(
        'metadata',
        jsonEncode(metadata),
        contentType: MediaType('application', 'json'),
      ))
      ..files.add(http.MultipartFile.fromString(
        'worker.js',
        bundle,
        filename: 'worker.js',
        contentType: MediaType('application', 'javascript+module'),
      ));

    final streamed = await _client.send(request).timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamed);
    final data = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
      throw WorkerDeploymentException('Cloudflare Worker upload failed: ${_cloudflareError(data, response.statusCode)}');
    }
  }

  Future<void> _enableWorkerSubdomain(WorkerDeploymentConfig c) async {
    final response = await _client.post(
      Uri.parse('$_cloudflareApi/accounts/${c.cloudflareAccountId}/workers/scripts/${Uri.encodeComponent(c.workerName)}/subdomain'),
      headers: {..._cfHeaders(c), 'content-type': 'application/json'},
      body: jsonEncode({'enabled': true, 'previews_enabled': false}),
    ).timeout(const Duration(seconds: 30));
    final data = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
      throw WorkerDeploymentException('Could not enable the Worker URL: ${_cloudflareError(data, response.statusCode)}');
    }
  }

  Future<void> _configureCron(WorkerDeploymentConfig c) async {
    final response = await _client.put(
      Uri.parse('$_cloudflareApi/accounts/${c.cloudflareAccountId}/workers/scripts/${Uri.encodeComponent(c.workerName)}/schedules'),
      headers: {..._cfHeaders(c), 'content-type': 'application/json'},
      body: jsonEncode([{'cron': '*/5 * * * *'}]),
    ).timeout(const Duration(seconds: 30));
    final data = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
      throw WorkerDeploymentException('Worker deployed, but the automatic backup schedule could not be configured: ${_cloudflareError(data, response.statusCode)}');
    }
  }

  Future<void> _waitForHealthyWorker(String workerUrl) async {
    Object? lastError;
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        final response = await _client.get(Uri.parse('$workerUrl/health')).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final data = _decodeJson(response.body);
          if (data['ok'] == true &&
              data['service'] == 'koinly-sync' &&
              data['databaseReachable'] == true &&
              data['schemaReady'] == true &&
              data['registrationMode'] == 'first-user' &&
              data['telegramBackupAvailable'] == true &&
              data['googleDriveBackupAvailable'] == true &&
              data['analyticsUploadAvailable'] == true &&
              data['realtimeSyncAvailable'] == true &&
              data['profileMediaSyncAvailable'] == true) {
            return;
          }
          final missing = data['missingTables'];
          lastError = WorkerDeploymentException(
            missing is List && missing.isNotEmpty
                ? 'Worker is online, but the database schema is missing: ${missing.join(', ')}.'
                : 'Worker is online, but its health check is not ready yet.',
          );
        }
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw WorkerDeploymentException('The Worker was uploaded but did not become healthy in time. ${lastError ?? ''}'.trim());
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _cloudflareError(Map<String, dynamic> body, int status) {
    final errors = body['errors'];
    if (errors is List) {
      final messages = errors.whereType<Map>().map((error) => '${error['message'] ?? ''}'.trim()).where((value) => value.isNotEmpty).toList();
      if (messages.isNotEmpty) return messages.join(' · ');
    }
    return 'HTTP $status';
  }

  List<String> _splitSqlStatements(String source) {
    final statements = <String>[];
    final current = StringBuffer();
    String? quote;
    var lineComment = false;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      final next = index + 1 < source.length ? source[index + 1] : '';
      if (lineComment) {
        if (char == '\n') {
          lineComment = false;
          current.write(char);
        }
        continue;
      }
      if (quote == null && char == '-' && next == '-') {
        lineComment = true;
        index++;
        continue;
      }
      current.write(char);
      if (quote != null) {
        if (char == quote) {
          if (next == quote) {
            current.write(next);
            index++;
          } else {
            quote = null;
          }
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
      } else if (char == ';') {
        final value = current.toString().trim();
        if (value.isNotEmpty) statements.add(value);
        current.clear();
      }
    }
    final trailing = current.toString().trim();
    if (trailing.isNotEmpty) statements.add(trailing);
    return statements;
  }
}

String _pbkdf2PasswordHash(String password) {
  final random = Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
  final derived = _pbkdf2HmacSha256(utf8.encode(password), salt, 100000, 32);
  String b64url(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');
  return 'pbkdf2\$100000\$${b64url(salt)}\$${b64url(derived)}';
}

Uint8List _pbkdf2HmacSha256(List<int> password, List<int> salt, int iterations, int length) {
  final hmac = Hmac(sha256, password);
  final blocks = (length / 32).ceil();
  final output = BytesBuilder(copy: false);
  for (var block = 1; block <= blocks; block++) {
    final blockBytes = Uint8List(4)
      ..[0] = (block >> 24) & 0xff
      ..[1] = (block >> 16) & 0xff
      ..[2] = (block >> 8) & 0xff
      ..[3] = block & 0xff;
    var u = hmac.convert([...salt, ...blockBytes]).bytes;
    final t = Uint8List.fromList(u);
    for (var iteration = 1; iteration < iterations; iteration++) {
      u = hmac.convert(u).bytes;
      for (var index = 0; index < t.length; index++) {
        t[index] ^= u[index];
      }
    }
    output.add(t);
  }
  final bytes = output.takeBytes();
  return Uint8List.sublistView(bytes, 0, length);
}
