import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class PrefsStore {
  SharedPreferences? _prefs;
  Future<SharedPreferences> get prefs async => _prefs ??= await SharedPreferences.getInstance();

  Future<T> getEnum<T>(String key, Iterable<T> values, T fallback) async => enumByName(values, (await prefs).getString(key), fallback);
  Future<void> setEnum(String key, Object value) async => (await prefs).setString(key, enumName(value));
  Future<bool> getBool(String key, bool fallback) async => (await prefs).getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) async => (await prefs).setBool(key, value);
  Future<String> getString(String key, String fallback) async => (await prefs).getString(key) ?? fallback;
  Future<void> setString(String key, String value) async => (await prefs).setString(key, value);
  Future<int> getInt(String key, int fallback) async => (await prefs).getInt(key) ?? fallback;
  Future<void> setInt(String key, int value) async => (await prefs).setInt(key, value);
  Future<List<String>> getStringList(String key) async => (await prefs).getStringList(key) ?? const [];
  Future<void> setStringList(String key, List<String> value) async => (await prefs).setStringList(key, value);
}

class SecureCredentialStore {
  SecureCredentialStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _cloudSyncPinKey = 'koinly_cloud_sync_pin';
  static const _mongoUrlKey = 'koinly_sync_mongodb_url';
  static const _mongoSyncPinKey = 'koinly_sync_mongodb_pin';
  static const _tursoAuthTokenKey = 'koinly_sync_turso_auth_token';
  static const _accessTokenKey = 'koinly_account_access_token';
  static const _refreshTokenKey = 'koinly_account_refresh_token';

  Future<String> readCloudSyncPin() async => await _storage.read(key: _cloudSyncPinKey) ?? '';
  Future<void> writeCloudSyncPin(String value) => _writeOrDelete(_cloudSyncPinKey, value);

  Future<String> readMongoDbUrl() async => await _storage.read(key: _mongoUrlKey) ?? '';
  Future<void> writeMongoDbUrl(String value) => _writeOrDelete(_mongoUrlKey, value);

  Future<String> readMongoDbSyncPin() async => await _storage.read(key: _mongoSyncPinKey) ?? '';
  Future<void> writeMongoDbSyncPin(String value) => _writeOrDelete(_mongoSyncPinKey, value);

  Future<String> readTursoAuthToken() async => await _storage.read(key: _tursoAuthTokenKey) ?? '';
  Future<void> writeTursoAuthToken(String value) => _writeOrDelete(_tursoAuthTokenKey, value);

  Future<String> readAccessToken() async => await _storage.read(key: _accessTokenKey) ?? '';
  Future<void> writeAccessToken(String value) => _writeOrDelete(_accessTokenKey, value);

  Future<String> readRefreshToken() async => await _storage.read(key: _refreshTokenKey) ?? '';
  Future<void> writeRefreshToken(String value) => _writeOrDelete(_refreshTokenKey, value);

  Future<void> clearAccountTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<void> _writeOrDelete(String key, String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: normalized);
    }
  }
}
