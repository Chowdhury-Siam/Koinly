import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const int kProfileMediaMaxBytes = 500 * 1024;
const String kProfileMediaSizeMessage = 'Profile media must be 500 KB or smaller.';

enum ProfileMediaKind { photo, gif, video }

enum ProfileMediaPermissionState {
  notRequired,
  granted,
  denied,
  permanentlyDenied,
}

class ProfileMediaException implements Exception {
  const ProfileMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StoredProfileMedia {
  const StoredProfileMedia({
    required this.path,
    required this.originalName,
    required this.kind,
    required this.sizeBytes,
  });

  final String path;
  final String originalName;
  final ProfileMediaKind kind;
  final int sizeBytes;
}

class ProfileMediaStorage {
  const ProfileMediaStorage();

  static const Set<String> photoExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };
  static const Set<String> gifExtensions = {'gif'};
  static const Set<String> videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'webm',
  };

  static const List<String> allowedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'mp4',
    'mov',
    'm4v',
    'webm',
  ];

  static ProfileMediaKind? kindForFileName(String name) {
    final extension = p.extension(name).replaceFirst('.', '').toLowerCase();
    if (photoExtensions.contains(extension)) return ProfileMediaKind.photo;
    if (gifExtensions.contains(extension)) return ProfileMediaKind.gif;
    if (videoExtensions.contains(extension)) return ProfileMediaKind.video;
    return null;
  }

  static void validateSelection({required String name, required int sizeBytes}) {
    if (sizeBytes > kProfileMediaMaxBytes) {
      throw const ProfileMediaException(kProfileMediaSizeMessage);
    }
    if (sizeBytes <= 0) {
      throw const ProfileMediaException('The selected profile media file is empty.');
    }
    if (kindForFileName(name) == null) {
      throw const ProfileMediaException('Choose a JPG, PNG, WebP, GIF, MP4, MOV, M4V, or WebM file.');
    }
  }

  Future<StoredProfileMedia> save({
    required String originalName,
    Uint8List? bytes,
    String? sourcePath,
  }) async {
    if (bytes == null && (sourcePath == null || sourcePath.trim().isEmpty)) {
      throw const ProfileMediaException('The selected profile media could not be read.');
    }

    final sourceFile = sourcePath == null || sourcePath.trim().isEmpty ? null : File(sourcePath);
    late final Uint8List actualBytes;
    if (bytes != null) {
      validateSelection(name: originalName, sizeBytes: bytes.length);
      actualBytes = bytes;
    } else {
      if (sourceFile == null || !await sourceFile.exists()) {
        throw const ProfileMediaException('The selected profile media could not be read.');
      }
      final sourceSize = await sourceFile.length();
      validateSelection(name: originalName, sizeBytes: sourceSize);
      actualBytes = await sourceFile.readAsBytes();
    }
    validateSelection(name: originalName, sizeBytes: actualBytes.length);
    final kind = kindForFileName(originalName)!;
    final extension = p.extension(originalName).replaceFirst('.', '').toLowerCase();
    final supportDirectory = await getApplicationSupportDirectory();
    final mediaDirectory = Directory(p.join(supportDirectory.path, 'profile_media'));
    await mediaDirectory.create(recursive: true);

    final target = File(
      p.join(
        mediaDirectory.path,
        'profile_${DateTime.now().microsecondsSinceEpoch}.$extension',
      ),
    );
    await target.writeAsBytes(actualBytes, flush: true);

    await for (final entity in mediaDirectory.list()) {
      if (entity is File && entity.path != target.path) {
        try {
          await entity.delete();
        } catch (_) {
          // A stale preview can remain locked briefly on Windows. It is safe to
          // retry cleanup on the next replacement or removal.
        }
      }
    }

    return StoredProfileMedia(
      path: target.path,
      originalName: originalName,
      kind: kind,
      sizeBytes: actualBytes.length,
    );
  }

  Future<void> remove(String path) async {
    if (path.trim().isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class ProfileMediaPermissionService {
  const ProfileMediaPermissionService();

  static const MethodChannel _channel = MethodChannel('com.koinly.siam/profile_media');

  Future<ProfileMediaPermissionState> check() async {
    if (!Platform.isAndroid) return ProfileMediaPermissionState.notRequired;
    try {
      final state = await _channel.invokeMethod<String>('checkPermission');
      return _decode(state);
    } on PlatformException {
      return ProfileMediaPermissionState.denied;
    } on MissingPluginException {
      return ProfileMediaPermissionState.denied;
    }
  }

  Future<ProfileMediaPermissionState> request() async {
    if (!Platform.isAndroid) return ProfileMediaPermissionState.notRequired;
    try {
      final state = await _channel.invokeMethod<String>('requestPermission');
      return _decode(state);
    } on PlatformException {
      return ProfileMediaPermissionState.denied;
    } on MissingPluginException {
      return ProfileMediaPermissionState.denied;
    }
  }

  Future<bool> openSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  ProfileMediaPermissionState _decode(String? value) {
    switch (value) {
      case 'granted':
        return ProfileMediaPermissionState.granted;
      case 'permanentlyDenied':
        return ProfileMediaPermissionState.permanentlyDenied;
      case 'notRequired':
        return ProfileMediaPermissionState.notRequired;
      default:
        return ProfileMediaPermissionState.denied;
    }
  }
}

String profileMediaKindLabel(ProfileMediaKind kind) {
  switch (kind) {
    case ProfileMediaKind.photo:
      return 'Photo';
    case ProfileMediaKind.gif:
      return 'GIF';
    case ProfileMediaKind.video:
      return 'Short video';
  }
}

String formatProfileMediaSize(int bytes) {
  if (bytes <= 0) return 'Unknown size';
  return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
}
