import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskman/systems/task.dart';

class MicrosoftIntegration {
  const MicrosoftIntegration({
    required this.userId,
    this.accountEmail,
    this.displayName,
    this.tenantId,
    this.clientId,
    this.targetProjectId,
    this.autoImportEnabled = true,
    this.linkedAt,
    this.lastSyncedAt,
    this.lastSyncedTaskCount = 0,
    this.lastSyncError,
  });

  final String userId;
  final String? accountEmail;
  final String? displayName;
  final String? tenantId;
  final String? clientId;
  final String? targetProjectId;
  final bool autoImportEnabled;
  final DateTime? linkedAt;
  final DateTime? lastSyncedAt;
  final int lastSyncedTaskCount;
  final String? lastSyncError;

  bool get isConnected => linkedAt != null;

  bool get hasTargetProject =>
      targetProjectId != null && targetProjectId!.trim().isNotEmpty;

  MicrosoftIntegration copyWith({
    String? accountEmail,
    String? displayName,
    String? tenantId,
    String? clientId,
    String? targetProjectId,
    bool? autoImportEnabled,
    DateTime? linkedAt,
    DateTime? lastSyncedAt,
    int? lastSyncedTaskCount,
    String? lastSyncError,
  }) {
    return MicrosoftIntegration(
      userId: userId,
      accountEmail: accountEmail ?? this.accountEmail,
      displayName: displayName ?? this.displayName,
      tenantId: tenantId ?? this.tenantId,
      clientId: clientId ?? this.clientId,
      targetProjectId: targetProjectId ?? this.targetProjectId,
      autoImportEnabled: autoImportEnabled ?? this.autoImportEnabled,
      linkedAt: linkedAt ?? this.linkedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastSyncedTaskCount: lastSyncedTaskCount ?? this.lastSyncedTaskCount,
      lastSyncError: lastSyncError ?? this.lastSyncError,
    );
  }

  factory MicrosoftIntegration.disconnected(String userId) {
    return MicrosoftIntegration(userId: userId);
  }

  factory MicrosoftIntegration.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return MicrosoftIntegration(
      userId: doc.id,
      accountEmail: _readString(data['accountEmail']),
      displayName: _readString(data['displayName']),
      tenantId: _readString(data['tenantId']),
      clientId: _readString(data['clientId']),
      targetProjectId: _readString(data['targetProjectId']),
      autoImportEnabled: data['autoImportEnabled'] as bool? ?? true,
      linkedAt: readDateTime(data['linkedAt']),
      lastSyncedAt: readDateTime(data['lastSyncedAt']),
      lastSyncedTaskCount: data['lastSyncedTaskCount'] as int? ?? 0,
      lastSyncError: _readString(data['lastSyncError']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'accountEmail': accountEmail,
      'displayName': displayName,
      'tenantId': tenantId,
      'clientId': clientId,
      'targetProjectId': targetProjectId,
      'autoImportEnabled': autoImportEnabled,
      'linkedAt': linkedAt == null ? null : Timestamp.fromDate(linkedAt!),
      'lastSyncedAt': lastSyncedAt == null
          ? null
          : Timestamp.fromDate(lastSyncedAt!),
      'lastSyncedTaskCount': lastSyncedTaskCount,
      'lastSyncError': lastSyncError,
    };
  }

  static String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
