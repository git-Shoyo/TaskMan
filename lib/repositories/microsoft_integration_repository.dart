import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:taskman/systems/microsoft_integration.dart';

class MicrosoftGraphException implements Exception {
  const MicrosoftGraphException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() {
    return 'Microsoft Graph request failed ($statusCode): $message';
  }
}

class MicrosoftPlannerSyncResult {
  const MicrosoftPlannerSyncResult({required this.syncedTaskCount});

  final int syncedTaskCount;
}

class MicrosoftDeviceCodeSession {
  const MicrosoftDeviceCodeSession({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
    this.message,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
  final String? message;

  factory MicrosoftDeviceCodeSession.fromJson(Map<String, dynamic> data) {
    return MicrosoftDeviceCodeSession(
      deviceCode: _readString(data['device_code']) ?? '',
      userCode: _readString(data['user_code']) ?? '',
      verificationUri: _readString(data['verification_uri']) ?? '',
      expiresIn: _readInt(data['expires_in']) ?? 900,
      interval: _readInt(data['interval']) ?? 5,
      message: _readString(data['message']),
    );
  }
}

class MicrosoftDeviceCodeToken {
  const MicrosoftDeviceCodeToken({required this.accessToken});

  final String accessToken;
}

class MicrosoftDeviceCodeException implements Exception {
  const MicrosoftDeviceCodeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() {
    return 'Microsoft device code failed ($code): $message';
  }
}

class MicrosoftDeviceCodeCancelledException implements Exception {
  const MicrosoftDeviceCodeCancelledException();
}

class MicrosoftGraphUserProfile {
  const MicrosoftGraphUserProfile({
    this.displayName,
    this.mail,
    this.userPrincipalName,
  });

  final String? displayName;
  final String? mail;
  final String? userPrincipalName;

  String? get accountEmail => mail ?? userPrincipalName;

  factory MicrosoftGraphUserProfile.fromJson(Map<String, dynamic> data) {
    return MicrosoftGraphUserProfile(
      displayName: _readString(data['displayName']),
      mail: _readString(data['mail']),
      userPrincipalName: _readString(data['userPrincipalName']),
    );
  }
}

class MicrosoftIntegrationRepository {
  MicrosoftIntegrationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _integrations =>
      _firestore.collection('microsoftIntegrations');

  DocumentReference<Map<String, dynamic>> _integrationDoc(String userId) {
    return _integrations.doc(userId);
  }

  Stream<MicrosoftIntegration> watchIntegration(String userId) {
    return _integrationDoc(userId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return MicrosoftIntegration.disconnected(userId);
      }

      return MicrosoftIntegration.fromFirestore(snapshot);
    });
  }

  Future<void> saveLinkedAccount({
    required String userId,
    String? accountEmail,
    String? displayName,
    String? tenantId,
    String? clientId,
    required String targetProjectId,
    required bool autoImportEnabled,
  }) async {
    final now = DateTime.now();

    await _integrationDoc(userId).set({
      'accountEmail': _emptyToNull(accountEmail),
      'displayName': _emptyToNull(displayName),
      'tenantId': _emptyToNull(tenantId),
      'clientId': _emptyToNull(clientId),
      'targetProjectId': _emptyToNull(targetProjectId),
      'autoImportEnabled': autoImportEnabled,
      'linkedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'lastSyncError': null,
    }, SetOptions(merge: true));
  }

  Future<void> updateSettings({
    required String userId,
    required String targetProjectId,
    required bool autoImportEnabled,
    String? clientId,
  }) async {
    final now = DateTime.now();

    await _integrationDoc(userId).set({
      'targetProjectId': _emptyToNull(targetProjectId),
      'autoImportEnabled': autoImportEnabled,
      if (clientId != null) 'clientId': _emptyToNull(clientId),
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  Future<void> recordSyncSuccess({
    required String userId,
    required int syncedTaskCount,
  }) async {
    final now = DateTime.now();

    await _integrationDoc(userId).set({
      'lastSyncedAt': Timestamp.fromDate(now),
      'lastSyncedTaskCount': syncedTaskCount,
      'lastSyncError': null,
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  Future<void> recordSyncFailure({
    required String userId,
    required Object error,
  }) async {
    final now = DateTime.now();

    await _integrationDoc(userId).set({
      'lastSyncError': error.toString(),
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  Future<void> disconnect(String userId) {
    return _integrationDoc(userId).delete();
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class MicrosoftDeviceCodeRepository {
  MicrosoftDeviceCodeRepository({http.Client? client})
    : _client = client ?? http.Client();

  static const defaultTenant = String.fromEnvironment(
    'MICROSOFT_TENANT',
    defaultValue: 'organizations',
  );
  static const defaultClientId = String.fromEnvironment(
    'MICROSOFT_CLIENT_ID',
    defaultValue: 'e89150a6-18fa-4ef0-9b1e-88aa85df3041',
  );
  static const scopes = 'User.Read Tasks.Read';

  final http.Client _client;

  Future<MicrosoftDeviceCodeSession> startDeviceCode({
    required String clientId,
    String tenant = defaultTenant,
  }) async {
    final normalizedClientId = clientId.trim();
    if (normalizedClientId.isEmpty) {
      throw StateError('Azure アプリケーション (client) ID を入力してください');
    }

    final response = await _client.post(
      Uri.parse(
        'https://login.microsoftonline.com/$tenant/oauth2/v2.0/devicecode',
      ),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'client_id': normalizedClientId, 'scope': scopes},
    );
    final body = _decodeJson(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _deviceCodeException(body);
    }

    final session = MicrosoftDeviceCodeSession.fromJson(body);
    if (session.deviceCode.isEmpty ||
        session.userCode.isEmpty ||
        session.verificationUri.isEmpty) {
      throw const MicrosoftDeviceCodeException(
        'invalid_response',
        'Microsoft の認証コードを取得できませんでした',
      );
    }

    return session;
  }

  Future<MicrosoftDeviceCodeToken> pollToken({
    required String clientId,
    required MicrosoftDeviceCodeSession session,
    String tenant = defaultTenant,
    required bool Function() isCancelled,
  }) async {
    var interval = session.interval <= 0 ? 5 : session.interval;
    final expiresAt = DateTime.now().add(Duration(seconds: session.expiresIn));

    while (DateTime.now().isBefore(expiresAt)) {
      await Future<void>.delayed(Duration(seconds: interval));

      if (isCancelled()) {
        throw const MicrosoftDeviceCodeCancelledException();
      }

      final response = await _client.post(
        Uri.parse(
          'https://login.microsoftonline.com/$tenant/oauth2/v2.0/token',
        ),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': clientId.trim(),
          'device_code': session.deviceCode,
        },
      );
      final body = _decodeJson(response.bodyBytes);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final accessToken = _readString(body['access_token']);
        if (accessToken == null) {
          throw const MicrosoftDeviceCodeException(
            'invalid_response',
            'Microsoft のアクセストークンを取得できませんでした',
          );
        }

        return MicrosoftDeviceCodeToken(accessToken: accessToken);
      }

      final errorCode = _readString(body['error']);
      if (errorCode == 'authorization_pending') {
        continue;
      }

      if (errorCode == 'slow_down') {
        interval += 5;
        continue;
      }

      throw _deviceCodeException(body);
    }

    throw const MicrosoftDeviceCodeException(
      'expired_token',
      'Microsoft 認証コードの有効期限が切れました',
    );
  }

  static MicrosoftDeviceCodeException _deviceCodeException(
    Map<String, dynamic> body,
  ) {
    return MicrosoftDeviceCodeException(
      _readString(body['error']) ?? 'unknown_error',
      _readString(body['error_description']) ??
          _readString(body['message']) ??
          'Microsoft 認証に失敗しました',
    );
  }
}

class MicrosoftPlannerRepository {
  MicrosoftPlannerRepository({
    FirebaseFirestore? firestore,
    http.Client? client,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _client = client ?? http.Client();

  static const source = 'microsoft-planner';

  final FirebaseFirestore _firestore;
  final http.Client _client;

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _firestore.collection('tasks');

  Future<MicrosoftGraphUserProfile> fetchCurrentUserProfile(
    String accessToken,
  ) async {
    final response = await _client.get(
      Uri.https('graph.microsoft.com', '/v1.0/me', {
        r'$select': 'displayName,mail,userPrincipalName',
      }),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    final body = _decodeJson(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MicrosoftGraphException(response.statusCode, _readGraphError(body));
    }

    return MicrosoftGraphUserProfile.fromJson(body);
  }

  Future<MicrosoftPlannerSyncResult> syncAssignedTasks({
    required String accessToken,
    required String targetProjectId,
    required String appUserId,
    required String assigneeName,
  }) async {
    final plannerTasks = await _fetchAssignedTasks(accessToken);
    var syncedCount = 0;

    for (final plannerTask in plannerTasks) {
      await _upsertPlannerTask(
        plannerTask,
        targetProjectId: targetProjectId,
        appUserId: appUserId,
        assigneeName: assigneeName,
      );
      syncedCount += 1;
    }

    return MicrosoftPlannerSyncResult(syncedTaskCount: syncedCount);
  }

  Future<List<_MicrosoftPlannerTask>> _fetchAssignedTasks(
    String accessToken,
  ) async {
    var nextUrl = Uri.parse(
      'https://graph.microsoft.com/v1.0/me/planner/tasks',
    );
    final tasks = <_MicrosoftPlannerTask>[];

    while (true) {
      final response = await _client.get(
        nextUrl,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );

      final body = _decodeJson(response.bodyBytes);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MicrosoftGraphException(
          response.statusCode,
          _readGraphError(body),
        );
      }

      final value = body['value'];
      if (value is List) {
        tasks.addAll(
          value.whereType<Map>().map(
            (item) => _MicrosoftPlannerTask.fromJson(item),
          ),
        );
      }

      final nextLink = body['@odata.nextLink'];
      if (nextLink is! String || nextLink.trim().isEmpty) {
        break;
      }

      nextUrl = Uri.parse(nextLink);
    }

    return tasks;
  }

  Future<void> _upsertPlannerTask(
    _MicrosoftPlannerTask plannerTask, {
    required String targetProjectId,
    required String appUserId,
    required String assigneeName,
  }) async {
    final taskDoc = _tasks.doc(_taskDocumentId(appUserId, plannerTask.id));
    final now = DateTime.now();
    final taskData = _taskDataFromPlannerTask(
      plannerTask,
      targetProjectId: targetProjectId,
      appUserId: appUserId,
      assigneeName: assigneeName,
      now: now,
    );

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(taskDoc);

      if (!snapshot.exists) {
        transaction.set(taskDoc, {
          ...taskData,
          'createdAt': Timestamp.fromDate(plannerTask.createdAt ?? now),
        });
        return;
      }

      transaction.update(taskDoc, taskData);
    });
  }

  Map<String, dynamic> _taskDataFromPlannerTask(
    _MicrosoftPlannerTask plannerTask, {
    required String targetProjectId,
    required String appUserId,
    required String assigneeName,
    required DateTime now,
  }) {
    final title = plannerTask.title.trim().isEmpty
        ? 'Microsoft Planner のタスク'
        : plannerTask.title.trim();
    final planId = plannerTask.planId.trim();
    final bucketId = plannerTask.bucketId.trim();
    final memoLines = [
      'Microsoft Teams / Planner から同期しました。',
      if (planId.isNotEmpty) 'Plan ID: $planId',
      if (bucketId.isNotEmpty) 'Bucket ID: $bucketId',
    ];

    return {
      'title': title,
      'deadline': plannerTask.dueDate == null
          ? null
          : Timestamp.fromDate(plannerTask.dueDate!),
      'startDate': plannerTask.startDate == null
          ? null
          : Timestamp.fromDate(plannerTask.startDate!),
      'isDone': plannerTask.isDone,
      'memo': memoLines.join('\n'),
      'updatedAt': Timestamp.fromDate(now),
      'priority': _mapPlannerPriority(plannerTask.priority),
      'category': 'Microsoft Teams',
      'projectId': targetProjectId,
      'assigneeId': appUserId,
      'assigneeName': assigneeName,
      'estimatedTimeSeconds': null,
      'reminder': null,
      'tags': const ['Microsoft', 'Teams', 'Planner'],
      'externalSource': source,
      'externalId': plannerTask.id,
      'externalPlanId': planId.isEmpty ? null : planId,
      'externalBucketId': bucketId.isEmpty ? null : bucketId,
      'externalUpdatedAt': Timestamp.fromDate(now),
    };
  }

  static String _taskDocumentId(String appUserId, String plannerTaskId) {
    return [
      source,
      Uri.encodeComponent(appUserId),
      Uri.encodeComponent(plannerTaskId),
    ].join('-');
  }

  static int? _mapPlannerPriority(int? plannerPriority) {
    if (plannerPriority == null) {
      return null;
    }

    if (plannerPriority <= 1) {
      return 5;
    }
    if (plannerPriority <= 4) {
      return 4;
    }
    if (plannerPriority <= 7) {
      return 3;
    }
    return 2;
  }

  static Map<String, dynamic> _decodeJson(List<int> bodyBytes) {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static String _readGraphError(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }

    return 'Microsoft Graph からタスクを取得できませんでした';
  }
}

String? _readString(Object? value) {
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

Map<String, dynamic> _decodeJson(List<int> bodyBytes) {
  final decoded = jsonDecode(utf8.decode(bodyBytes));
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
}

class _MicrosoftPlannerTask {
  const _MicrosoftPlannerTask({
    required this.id,
    required this.title,
    required this.planId,
    required this.bucketId,
    this.createdAt,
    this.startDate,
    this.dueDate,
    this.completedAt,
    this.percentComplete,
    this.priority,
  });

  final String id;
  final String title;
  final String planId;
  final String bucketId;
  final DateTime? createdAt;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final int? percentComplete;
  final int? priority;

  bool get isDone => (percentComplete ?? 0) >= 100 || completedAt != null;

  factory _MicrosoftPlannerTask.fromJson(Map<dynamic, dynamic> data) {
    return _MicrosoftPlannerTask(
      id: _readString(data['id']) ?? '',
      title: _readString(data['title']) ?? '',
      planId: _readString(data['planId']) ?? '',
      bucketId: _readString(data['bucketId']) ?? '',
      createdAt: _readDateTime(data['createdDateTime']),
      startDate: _readDateTime(data['startDateTime']),
      dueDate: _readDateTime(data['dueDateTime']),
      completedAt: _readDateTime(data['completedDateTime']),
      percentComplete: _readInt(data['percentComplete']),
      priority: _readInt(data['priority']),
    );
  }

  static String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    final text = value as String?;
    if (text == null || text.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(text)?.toLocal();
  }
}
