class CloudSyncException implements Exception {
  const CloudSyncException(this.message, {this.code});

  final String message;
  final String? code;

  bool get approvalRequired => code == 'SYNC_APPROVAL_REQUIRED';

  @override
  String toString() => message;
}

class SyncAuthSession {
  const SyncAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.username,
    required this.userId,
    required this.deviceId,
    required this.accessExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String username;
  final String userId;
  final String deviceId;
  final DateTime accessExpiresAt;
}

enum TelegramBackupFrequency { daily, weekly, monthly }

class TelegramBackupSettings {
  const TelegramBackupSettings({
    required this.enabled,
    required this.tokenConfigured,
    required this.chatId,
    required this.frequency,
    required this.hour,
    required this.minute,
    required this.weekday,
    required this.monthDay,
    required this.timezoneOffsetMinutes,
    this.nextDueAt,
    this.lastSentAt,
    this.lastError,
  });

  const TelegramBackupSettings.defaults()
      : enabled = false,
        tokenConfigured = false,
        chatId = '',
        frequency = TelegramBackupFrequency.daily,
        hour = 2,
        minute = 0,
        weekday = DateTime.sunday,
        monthDay = 1,
        timezoneOffsetMinutes = 0,
        nextDueAt = null,
        lastSentAt = null,
        lastError = null;

  final bool enabled;
  final bool tokenConfigured;
  final String chatId;
  final TelegramBackupFrequency frequency;
  final int hour;
  final int minute;
  final int weekday;
  final int monthDay;
  final int timezoneOffsetMinutes;
  final DateTime? nextDueAt;
  final DateTime? lastSentAt;
  final String? lastError;

  factory TelegramBackupSettings.fromJson(Map<String, dynamic> data) {
    TelegramBackupFrequency parseFrequency(String value) {
      for (final item in TelegramBackupFrequency.values) {
        if (item.name == value) return item;
      }
      return TelegramBackupFrequency.daily;
    }

    DateTime? parseTime(dynamic value) {
      final millis = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      if (millis == null || millis <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }

    return TelegramBackupSettings(
      enabled: data['enabled'] == true,
      tokenConfigured: data['tokenConfigured'] == true,
      chatId: data['chatId']?.toString() ?? '',
      frequency: parseFrequency(data['frequency']?.toString() ?? ''),
      hour: ((data['hour'] as num?)?.toInt() ?? 2).clamp(0, 23).toInt(),
      minute: ((data['minute'] as num?)?.toInt() ?? 0).clamp(0, 59).toInt(),
      weekday: ((data['weekday'] as num?)?.toInt() ?? DateTime.sunday).clamp(DateTime.monday, DateTime.sunday).toInt(),
      monthDay: ((data['monthDay'] as num?)?.toInt() ?? 1).clamp(1, 31).toInt(),
      timezoneOffsetMinutes: ((data['timezoneOffsetMinutes'] as num?)?.toInt() ?? 0).clamp(-840, 840).toInt(),
      nextDueAt: parseTime(data['nextDueAt']),
      lastSentAt: parseTime(data['lastSentAt']),
      lastError: data['lastError']?.toString(),
    );
  }
}

class GoogleDriveAnalyticsSettings {
  const GoogleDriveAnalyticsSettings({
    required this.clientId,
    required this.clientSecretConfigured,
    required this.connected,
    required this.accountEmail,
    required this.folderName,
    this.connectedAt,
    this.lastUploadAt,
    this.lastError,
  });

  const GoogleDriveAnalyticsSettings.defaults()
      : clientId = '',
        clientSecretConfigured = false,
        connected = false,
        accountEmail = '',
        folderName = 'Koinly Analytics',
        connectedAt = null,
        lastUploadAt = null,
        lastError = null;

  final String clientId;
  final bool clientSecretConfigured;
  final bool connected;
  final String accountEmail;
  final String folderName;
  final DateTime? connectedAt;
  final DateTime? lastUploadAt;
  final String? lastError;

  factory GoogleDriveAnalyticsSettings.fromJson(Map<String, dynamic> data) {
    DateTime? parseTime(dynamic value) {
      final millis = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      if (millis == null || millis <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }

    return GoogleDriveAnalyticsSettings(
      clientId: data['clientId']?.toString() ?? '',
      clientSecretConfigured: data['clientSecretConfigured'] == true,
      connected: data['connected'] == true,
      accountEmail: data['accountEmail']?.toString() ?? '',
      folderName: data['folderName']?.toString().trim().isNotEmpty == true ? data['folderName'].toString() : 'Koinly Analytics',
      connectedAt: parseTime(data['connectedAt']),
      lastUploadAt: parseTime(data['lastUploadAt']),
      lastError: data['lastError']?.toString(),
    );
  }
}

class RemoteProfileMediaMetadata {
  const RemoteProfileMediaMetadata({
    required this.version,
    required this.originalName,
    required this.kind,
    required this.sizeBytes,
    required this.chunkCount,
    required this.scale,
    required this.alignmentX,
    required this.alignmentY,
    required this.updatedAt,
  });

  final String version;
  final String originalName;
  final String kind;
  final int sizeBytes;
  final int chunkCount;
  final double scale;
  final double alignmentX;
  final double alignmentY;
  final int updatedAt;

  factory RemoteProfileMediaMetadata.fromJson(Map<String, dynamic> data) {
    return RemoteProfileMediaMetadata(
      version: data['version']?.toString() ?? '',
      originalName: data['originalName']?.toString() ?? '',
      kind: data['kind']?.toString() ?? '',
      sizeBytes: (data['sizeBytes'] as num? ?? 0).toInt(),
      chunkCount: (data['chunkCount'] as num? ?? 0).toInt(),
      scale: (data['scale'] as num? ?? 1).toDouble().clamp(1.0, 3.0).toDouble(),
      alignmentX: (data['alignmentX'] as num? ?? 0).toDouble().clamp(-1.0, 1.0).toDouble(),
      alignmentY: (data['alignmentY'] as num? ?? 0).toDouble().clamp(-1.0, 1.0).toDouble(),
      updatedAt: (data['updatedAt'] as num? ?? 0).toInt(),
    );
  }
}
