import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'app_config.dart';
import 'update_service.dart';

class WorkerDeploymentConfig {
  const WorkerDeploymentConfig({
    required this.workerName,
    required this.cloudflareAccountId,
    required this.cloudflareApiToken,
    required this.tursoDatabaseUrl,
    required this.tursoAuthToken,
    required this.jwtSecret,
    required this.adminUsername,
    this.adminPassword = '',
    this.adminPasswordHash = '',
  });

  final String workerName;
  final String cloudflareAccountId;
  final String cloudflareApiToken;
  final String tursoDatabaseUrl;
  final String tursoAuthToken;
  final String jwtSecret;
  final String adminUsername;
  final String adminPassword;
  final String adminPasswordHash;
}

class WorkerDeploymentResult {
  const WorkerDeploymentResult({
    required this.workerUrl,
    required this.adminPasswordHash,
    required this.workerVersion,
  });

  final String workerUrl;
  final String adminPasswordHash;
  final String workerVersion;
}

class WorkerDeploymentException implements Exception {
  const WorkerDeploymentException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef WorkerDeploymentProgress = void Function(String message);

class WorkerDeploymentProfile {
  const WorkerDeploymentProfile({
    required this.workerName,
    required this.cloudflareAccountId,
    required this.cloudflareApiToken,
    required this.tursoDatabaseUrl,
    required this.tursoAuthToken,
    required this.jwtSecret,
    required this.adminUsername,
    required this.adminPasswordHash,
    required this.workerUrl,
    required this.workerVersion,
  });

  final String workerName;
  final String cloudflareAccountId;
  final String cloudflareApiToken;
  final String tursoDatabaseUrl;
  final String tursoAuthToken;
  final String jwtSecret;
  final String adminUsername;
  final String adminPasswordHash;
  final String workerUrl;
  final String workerVersion;

  WorkerDeploymentConfig toDeploymentConfig() => WorkerDeploymentConfig(
        workerName: workerName,
        cloudflareAccountId: cloudflareAccountId,
        cloudflareApiToken: cloudflareApiToken,
        tursoDatabaseUrl: tursoDatabaseUrl,
        tursoAuthToken: tursoAuthToken,
        jwtSecret: jwtSecret,
        adminUsername: adminUsername,
        adminPasswordHash: adminPasswordHash,
      );

  WorkerDeploymentProfile copyWith({String? workerUrl, String? workerVersion}) => WorkerDeploymentProfile(
        workerName: workerName,
        cloudflareAccountId: cloudflareAccountId,
        cloudflareApiToken: cloudflareApiToken,
        tursoDatabaseUrl: tursoDatabaseUrl,
        tursoAuthToken: tursoAuthToken,
        jwtSecret: jwtSecret,
        adminUsername: adminUsername,
        adminPasswordHash: adminPasswordHash,
        workerUrl: workerUrl ?? this.workerUrl,
        workerVersion: workerVersion ?? this.workerVersion,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'workerName': workerName,
        'cloudflareAccountId': cloudflareAccountId,
        'cloudflareApiToken': cloudflareApiToken,
        'tursoDatabaseUrl': tursoDatabaseUrl,
        'tursoAuthToken': tursoAuthToken,
        'jwtSecret': jwtSecret,
        'adminUsername': adminUsername,
        'adminPasswordHash': adminPasswordHash,
        'workerUrl': workerUrl,
        'workerVersion': workerVersion,
      };

  static WorkerDeploymentProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String value(String key) => '${raw[key] ?? ''}'.trim();
    final profile = WorkerDeploymentProfile(
      workerName: value('workerName'),
      cloudflareAccountId: value('cloudflareAccountId'),
      cloudflareApiToken: value('cloudflareApiToken'),
      tursoDatabaseUrl: value('tursoDatabaseUrl'),
      tursoAuthToken: value('tursoAuthToken'),
      jwtSecret: value('jwtSecret'),
      adminUsername: value('adminUsername'),
      adminPasswordHash: value('adminPasswordHash'),
      workerUrl: value('workerUrl'),
      workerVersion: value('workerVersion'),
    );
    if (profile.workerName.isEmpty ||
        profile.cloudflareAccountId.isEmpty ||
        profile.cloudflareApiToken.isEmpty ||
        profile.tursoDatabaseUrl.isEmpty ||
        profile.tursoAuthToken.isEmpty ||
        profile.jwtSecret.isEmpty ||
        profile.adminUsername.isEmpty ||
        profile.adminPasswordHash.isEmpty ||
        profile.workerUrl.isEmpty) {
      return null;
    }
    return profile;
  }
}

class WorkerDeploymentCredentialStore {
  WorkerDeploymentCredentialStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _profileKey = 'koinly_worker_auto_deployment_profile_v1';
  final FlutterSecureStorage _storage;

  Future<WorkerDeploymentProfile?> read() async {
    try {
      final encoded = await _storage.read(key: _profileKey);
      if (encoded == null || encoded.trim().isEmpty) return null;
      return WorkerDeploymentProfile.fromJson(jsonDecode(encoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(WorkerDeploymentProfile profile) async {
    await _storage.write(key: _profileKey, value: jsonEncode(profile.toJson()));
  }

  Future<void> clear() => _storage.delete(key: _profileKey);
}

enum WorkerAutoUpdateOutcome { noSavedDeployment, inactiveDeployment, alreadyCurrent, updated }

class WorkerAutoUpdateResult {
  const WorkerAutoUpdateResult(this.outcome, {this.message = '', this.workerUrl = ''});

  final WorkerAutoUpdateOutcome outcome;
  final String message;
  final String workerUrl;
}

class WorkerAutoUpdateService {
  WorkerAutoUpdateService({
    WorkerDeploymentCredentialStore? credentialStore,
    http.Client? client,
  })  : _credentialStore = credentialStore ?? WorkerDeploymentCredentialStore(),
        _client = client ?? http.Client();

  final WorkerDeploymentCredentialStore _credentialStore;
  final http.Client _client;

  void close() => _client.close();

  Future<WorkerAutoUpdateResult> checkAndUpdate({
    required String activeWorkerUrl,
    WorkerDeploymentProgress? onProgress,
  }) async {
    final profile = await _credentialStore.read();
    if (profile == null) {
      return const WorkerAutoUpdateResult(WorkerAutoUpdateOutcome.noSavedDeployment);
    }

    final active = _normalizeWorkerUrl(activeWorkerUrl);
    final saved = _normalizeWorkerUrl(profile.workerUrl);
    if (active.isEmpty || active != saved) {
      return const WorkerAutoUpdateResult(
        WorkerAutoUpdateOutcome.inactiveDeployment,
        message: 'Automatic Worker update skipped because this device is using a different Worker.',
      );
    }

    final installedVersion = SemanticVersion.tryParse(appVersion);
    final savedVersion = SemanticVersion.tryParse(profile.workerVersion);
    if (installedVersion != null && savedVersion != null && savedVersion.compareTo(installedVersion) >= 0) {
      return WorkerAutoUpdateResult(
        WorkerAutoUpdateOutcome.alreadyCurrent,
        message: 'Worker is already current.',
        workerUrl: profile.workerUrl,
      );
    }

    onProgress?.call('Checking Worker version…');
    final remoteVersion = await _fetchWorkerVersion(profile.workerUrl);
    final remoteSemantic = SemanticVersion.tryParse(remoteVersion ?? '');
    if (installedVersion != null && remoteSemantic != null && remoteSemantic.compareTo(installedVersion) >= 0) {
      try {
        await _credentialStore.write(profile.copyWith(workerVersion: remoteVersion));
      } catch (_) {
        // The remote Worker is already current, so a secure-storage refresh
        // failure must not turn a healthy deployment into an update failure.
      }
      return WorkerAutoUpdateResult(
        WorkerAutoUpdateOutcome.alreadyCurrent,
        message: 'Worker is already current.',
        workerUrl: profile.workerUrl,
      );
    }

    onProgress?.call('A newer Koinly Worker is available. Updating automatically…');
    final deployment = WorkerDeploymentService(client: _client);
    final result = await deployment.deploy(
      profile.toDeploymentConfig(),
      onProgress: onProgress ?? (_) {},
    );
    var profileSaved = true;
    try {
      await _credentialStore.write(profile.copyWith(
        workerUrl: result.workerUrl,
        workerVersion: result.workerVersion,
      ));
    } catch (_) {
      profileSaved = false;
    }
    return WorkerAutoUpdateResult(
      WorkerAutoUpdateOutcome.updated,
      message: profileSaved
          ? 'Worker updated automatically to ${result.workerVersion}.'
          : 'Worker updated automatically to ${result.workerVersion}, but the secure deployment profile could not be refreshed. Future automatic updates may require Deploy Database.',
      workerUrl: result.workerUrl,
    );
  }

  Future<String?> _fetchWorkerVersion(String workerUrl) async {
    try {
      final response = await _client
          .get(Uri.parse('${_normalizeWorkerUrl(workerUrl)}/health'), headers: const {'accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final value = '${decoded['workerVersion'] ?? ''}'.trim();
      return value.isEmpty || value == 'legacy' ? null : value;
    } catch (_) {
      return null;
    }
  }
}

String _normalizeWorkerUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final withoutSlash = trimmed.replaceFirst(RegExp(r'/+$'), '');
  return withoutSlash.toLowerCase();
}

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
    final passwordHash = config.adminPasswordHash.trim().isNotEmpty
        ? config.adminPasswordHash.trim()
        : await compute(_pbkdf2PasswordHash, config.adminPassword);

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
    await _waitForHealthyWorker(workerUrl, onProgress: onProgress);

    onProgress('Worker deployed successfully.');
    return WorkerDeploymentResult(
      workerUrl: workerUrl,
      adminPasswordHash: passwordHash,
      workerVersion: appVersion,
    );
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
        adminPasswordHash: c.adminPasswordHash.trim(),
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
    final passwordHashValid = RegExp(r'^pbkdf2\$100000\$[A-Za-z0-9_-]+\$[A-Za-z0-9_-]+$').hasMatch(c.adminPasswordHash);
    if (c.adminPasswordHash.isNotEmpty && !passwordHashValid) {
      throw const WorkerDeploymentException('Saved administrator credentials are invalid. Enter the administrator password again.');
    }
    if (c.adminPasswordHash.isEmpty && (c.adminPassword.length < 12 || c.adminPassword.length > 256)) {
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
    // Turso/libSQL's remote database API is the Hrana HTTP pipeline endpoint.
    // There is no guaranteed `/version` route on a Turso database host, so a
    // GET there can return 404 even when both the database URL and auth token
    // are completely valid. Verify the exact API Koinly will use instead with
    // a read-only SELECT.
    final response = await _client.post(
      Uri.parse('${_tursoHttpBase(c.tursoDatabaseUrl)}/v2/pipeline'),
      headers: {
        'authorization': 'Bearer ${c.tursoAuthToken}',
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode({
        'baton': null,
        'requests': [
          {
            'type': 'execute',
            'stmt': {
              'sql': 'SELECT 1 AS koinly_connection_test',
              'want_rows': true,
            },
          },
          {'type': 'close'},
        ],
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw WorkerDeploymentException(
          'Turso rejected the database auth token (HTTP ${response.statusCode}). Check the database auth token and try again.',
        );
      }
      if (response.statusCode == 404) {
        throw const WorkerDeploymentException(
          'Turso could not find that database endpoint. Re-copy the libsql:// database URL from Turso and try again.',
        );
      }
      throw WorkerDeploymentException(
        'Could not connect to the Turso database (HTTP ${response.statusCode}). Check the database URL and database auth token.',
      );
    }

    final data = _decodeJson(response.body);
    final rawResults = data['results'];
    if (rawResults is! List || rawResults.isEmpty) {
      throw const WorkerDeploymentException('Turso returned an invalid connection-check response.');
    }
    for (final entry in rawResults) {
      if (entry is! Map || entry['type'] != 'error') continue;
      final error = entry['error'];
      final message = error is Map ? '${error['message'] ?? 'Database error'}'.trim() : 'Database error';
      throw WorkerDeploymentException('Turso connection check failed: $message');
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
          'stmt': {
            'sql': statement,
            'want_rows': true,
          },
        },
      {'type': 'close'},
    ];
    final response = await _client.post(
      Uri.parse('${_tursoHttpBase(c.tursoDatabaseUrl)}/v2/pipeline'),
      headers: {
        'authorization': 'Bearer ${c.tursoAuthToken}',
        'content-type': 'application/json',
      },
      body: jsonEncode({'baton': null, 'requests': requests}),
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
        // The Worker uses @libsql/client/web (HTTP transport). Keep the UI on Turso's
        // canonical libsql:// value, but bind the equivalent HTTPS endpoint so
        // Cloudflare never has to negotiate a WebSocket-style libsql scheme.
        {'type': 'secret_text', 'name': 'TURSO_DATABASE_URL', 'text': _tursoHttpBase(c.tursoDatabaseUrl)},
        {'type': 'secret_text', 'name': 'TURSO_AUTH_TOKEN', 'text': c.tursoAuthToken},
        {'type': 'secret_text', 'name': 'JWT_SECRET', 'text': c.jwtSecret},
        {'type': 'secret_text', 'name': 'ADMIN_USERNAME', 'text': c.adminUsername},
        {'type': 'secret_text', 'name': 'ADMIN_PASSWORD_HASH', 'text': adminPasswordHash},
        {'type': 'plain_text', 'name': 'ACCESS_TOKEN_TTL_SECONDS', 'text': '900'},
        {'type': 'plain_text', 'name': 'REFRESH_TOKEN_TTL_SECONDS', 'text': '2592000'},
        {'type': 'plain_text', 'name': 'MAX_SYNC_BATCH_SIZE', 'text': '100'},
        {'type': 'plain_text', 'name': 'MAX_SYNC_REPLACE_SIZE', 'text': '25000'},
        {'type': 'plain_text', 'name': 'KOINLY_WORKER_VERSION', 'text': appVersion},
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

  Future<void> _waitForHealthyWorker(
    String workerUrl, {
    required WorkerDeploymentProgress onProgress,
  }) async {
    // First-time workers.dev routes can take longer than a minute to finish
    // TLS/routing propagation. Match the more patient GitHub deployment path
    // and keep the user informed instead of reporting a false deployment
    // failure after only ~60 seconds.
    const maxAttempts = 24;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _client
            .get(
              Uri.parse('$workerUrl/health'),
              headers: const {'accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 20));
        final data = _decodeJson(response.body);
        final hasJson = data.isNotEmpty;

        if (response.statusCode == 200 &&
            data['ok'] == true &&
            data['service'] == 'koinly-sync' &&
            data['databaseReachable'] == true &&
            data['schemaReady'] == true &&
            data['registrationMode'] == 'first-user' &&
            data['telegramBackupAvailable'] == true &&
            data['googleDriveBackupAvailable'] == true &&
            data['analyticsUploadAvailable'] == true &&
            data['realtimeSyncAvailable'] == true &&
            data['profileMediaSyncAvailable'] == true &&
            data['workerVersion'] == appVersion) {
          return;
        }

        lastError = WorkerDeploymentException(_healthDiagnostic(
          statusCode: response.statusCode,
          data: data,
          body: response.body,
        ));

        // Keep 404/52x/temporary 5xx responses in the normal propagation
        // path. For a JSON 503 from Koinly itself, the diagnostic below keeps
        // the actual database/schema/runtime reason so the final error is
        // actionable if it never recovers.
        if (attempt == 1 || attempt % 3 == 0 || hasJson) {
          onProgress('Worker health check $attempt/$maxAttempts: ${_healthProgressSummary(response.statusCode, data)}');
        }
      } catch (error) {
        lastError = error;
        if (attempt == 1 || attempt % 3 == 0) {
          onProgress('Worker health check $attempt/$maxAttempts: waiting for workers.dev route propagation…');
        }
      }

      if (attempt < maxAttempts) {
        await Future<void>.delayed(const Duration(seconds: 8));
      }
    }

    final detail = lastError is WorkerDeploymentException
        ? lastError.message
        : 'Cloudflare did not make the workers.dev route reachable in time.';
    throw WorkerDeploymentException(
      'The Worker was uploaded, but its health check did not become ready. $detail',
    );
  }

  String _healthProgressSummary(int statusCode, Map<String, dynamic> data) {
    if (data.isEmpty) {
      if (statusCode == 404) return 'workers.dev route is still propagating…';
      if (statusCode >= 500) return 'Cloudflare is still starting the Worker (HTTP $statusCode)…';
      return 'HTTP $statusCode; waiting for the deployed Worker…';
    }
    if (data['databaseReachable'] == false) return 'Worker is online; waiting for the Turso connection…';
    final missing = data['missingTables'];
    if (data['schemaReady'] == false && missing is List && missing.isNotEmpty) {
      return 'Worker is online; waiting for database schema readiness…';
    }
    if (data['realtimeSyncAvailable'] != true) return 'Worker is online; waiting for realtime sync binding…';
    if (data['workerVersion'] != appVersion) return 'Cloudflare is still serving the previous Worker version…';
    return 'Worker is online; waiting for the full capability check…';
  }

  String _healthDiagnostic({
    required int statusCode,
    required Map<String, dynamic> data,
    required String body,
  }) {
    if (data.isNotEmpty) {
      if (data['databaseReachable'] == false) {
        final rawError = '${data['error'] ?? ''}'.trim();
        final safeError = rawError
            .replaceAll(RegExp(r'https?://[^\s]+'), '[database endpoint]')
            .replaceAll(RegExp(r'libsql://[^\s]+'), '[database endpoint]')
            .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._-]+', caseSensitive: false), 'Bearer [redacted]')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return safeError.isEmpty
            ? 'The Worker is online, but it cannot reach Turso. The in-app connection test passed, so Cloudflare may still be propagating the new Worker secrets.'
            : 'The Worker is online, but its Turso connection failed: ${safeError.length > 220 ? '${safeError.substring(0, 220)}…' : safeError}';
      }
      final missing = data['missingTables'];
      if (data['schemaReady'] == false && missing is List && missing.isNotEmpty) {
        return 'The Worker is online, but these database tables are still missing: ${missing.join(', ')}.';
      }
      if (data['realtimeSyncAvailable'] != true) {
        return 'The Worker is online, but the Cloudflare Durable Object binding for realtime sync is not active yet.';
      }
      if (data['workerVersion'] != appVersion) {
        return 'Cloudflare is still serving Worker version ${data['workerVersion'] ?? 'legacy'} instead of $appVersion.';
      }
      return 'The Worker returned HTTP $statusCode, but its Koinly capability contract is not ready yet.';
    }

    if (statusCode == 404) {
      return 'The workers.dev URL still returns HTTP 404. Cloudflare accepted the upload, but the public route did not finish propagating.';
    }
    if (statusCode >= 500) {
      return 'The workers.dev URL returned HTTP $statusCode while the Worker was starting.';
    }
    final compactBody = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compactBody.isNotEmpty) {
      final preview = compactBody.length > 180 ? '${compactBody.substring(0, 180)}…' : compactBody;
      return 'The Worker health URL returned HTTP $statusCode instead of Koinly health JSON: $preview';
    }
    return 'The Worker health URL returned HTTP $statusCode.';
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
