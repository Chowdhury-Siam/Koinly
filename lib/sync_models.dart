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
    required this.email,
    required this.userId,
    required this.deviceId,
    required this.accessExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String email;
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
