import 'dart:typed_data';

import 'package:flutter/services.dart';

class AndroidBackupDirectorySelection {
  const AndroidBackupDirectorySelection({required this.uri, required this.label});

  final String uri;
  final String label;
}

class AndroidSafBackupFile {
  const AndroidSafBackupFile({required this.name, required this.lastModified});

  final String name;
  final int lastModified;
}

class AndroidSafBackupStore {
  static const MethodChannel _channel = MethodChannel('com.koinly.siam/backup_storage');

  static Future<AndroidBackupDirectorySelection?> pickDirectory() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('pickDirectory');
    if (raw == null) return null;
    final uri = raw['uri']?.toString().trim() ?? '';
    if (uri.isEmpty) return null;
    final label = raw['label']?.toString().trim() ?? '';
    return AndroidBackupDirectorySelection(uri: uri, label: label.isEmpty ? 'Selected Android folder' : label);
  }

  static Future<bool> canWrite(String uri) async {
    return await _channel.invokeMethod<bool>('canWrite', {'uri': uri}) ?? false;
  }

  static Future<void> writeFile({required String uri, required String name, required Uint8List bytes}) async {
    await _channel.invokeMethod<void>('writeFile', {
      'uri': uri,
      'name': name,
      'bytes': bytes,
    });
  }

  static Future<List<AndroidSafBackupFile>> listFiles(String uri) async {
    final raw = await _channel.invokeListMethod<dynamic>('listFiles', {'uri': uri}) ?? const [];
    return raw.whereType<Map>().map((entry) {
      return AndroidSafBackupFile(
        name: entry['name']?.toString() ?? '',
        lastModified: (entry['lastModified'] as num? ?? 0).toInt(),
      );
    }).where((entry) => entry.name.isNotEmpty).toList();
  }

  static Future<void> deleteFile({required String uri, required String name}) async {
    await _channel.invokeMethod<void>('deleteFile', {'uri': uri, 'name': name});
  }
}
