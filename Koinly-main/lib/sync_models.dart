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
