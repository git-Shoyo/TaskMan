import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

typedef TaskNotificationTapHandler = void Function(String taskId);

const _taskReminderChannelId = 'task_reminders';
const _taskReminderChannelName = 'タスクリマインダー';
const _taskNotificationPayloadPrefix = 'task:';
const _maximumScheduledReminders = 64;

final DateFormat _notificationTimeFormat = DateFormat('yyyy/MM/dd HH:mm');

@pragma('vm:entry-point')
void taskNotificationTapBackground(NotificationResponse response) {}

class TaskNotificationService {
  TaskNotificationService._();

  static final TaskNotificationService instance = TaskNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  TaskNotificationTapHandler? _onTaskSelected;
  String? _pendingTaskId;
  final Set<int> _scheduledReminderIds = <int>{};
  bool _isInitialized = false;
  bool _permissionsRequested = false;
  AndroidScheduleMode _androidScheduleMode =
      AndroidScheduleMode.inexactAllowWhileIdle;

  bool get isInitialized => _isInitialized;

  bool get supportsScheduledNotifications {
    return !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;
  }

  bool get shouldShowDueTimeNativeReminderFallback {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows);
  }

  Future<void> initialize() async {
    if (_isInitialized || kIsWeb) {
      return;
    }

    await _configureLocalTimeZone();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(defaultActionName: '開く');
    const windowsSettings = WindowsInitializationSettings(
      appName: 'TaskMan',
      appUserModelId: 'Com.TaskMan.Desktop',
      guid: '8e73b7ec-4914-44bf-b7da-0a3a3f3efacd',
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: taskNotificationTapBackground,
    );

    await _captureLaunchNotification();
    _isInitialized = true;
  }

  void setTaskTapHandler(TaskNotificationTapHandler? handler) {
    _onTaskSelected = handler;
    final taskId = _pendingTaskId;
    if (handler == null || taskId == null) {
      return;
    }

    _pendingTaskId = null;
    Future<void>.microtask(() => handler(taskId));
  }

  Future<void> requestPermissions() async {
    if (!_isInitialized || _permissionsRequested || kIsWeb) {
      return;
    }

    _permissionsRequested = true;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    final canScheduleExactNotifications = await android
        ?.canScheduleExactNotifications();
    if (canScheduleExactNotifications == true) {
      _androidScheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> syncTaskReminders(
    Iterable<Task> tasks, {
    Map<String, Project> projectById = const {},
  }) async {
    if (!_isInitialized || !supportsScheduledNotifications) {
      return;
    }

    try {
      await requestPermissions();

      final now = DateTime.now();
      final scheduledTasks =
          tasks
              .where(
                (task) =>
                    !task.isDone &&
                    task.reminder != null &&
                    task.reminder!.isAfter(now),
              )
              .toList()
            ..sort((a, b) => a.reminder!.compareTo(b.reminder!));
      final limitedTasks = scheduledTasks
          .take(_maximumScheduledReminders)
          .toList();

      await _cancelPreviouslyScheduledReminders(limitedTasks);

      for (final task in limitedTasks) {
        await _scheduleTaskReminder(task, project: projectById[task.projectId]);
      }
    } catch (error, stackTrace) {
      _logNotificationError('Failed to sync task reminders', error, stackTrace);
    }
  }

  Future<void> showTaskReminderNowForDueTimeFallback(
    Task task, {
    Project? project,
  }) async {
    if (!shouldShowDueTimeNativeReminderFallback) {
      return;
    }

    await showTaskReminderNow(task, project: project);
  }

  Future<void> showTaskReminderNow(Task task, {Project? project}) async {
    if (!_isInitialized) {
      return;
    }

    try {
      await requestPermissions();
      await _plugin.show(
        id: _notificationIdForTask(task.id),
        title: 'リマインダー',
        body: _notificationBody(task, project: project),
        notificationDetails: _notificationDetails(project: project),
        payload: _payloadForTask(task.id),
      );
    } catch (error, stackTrace) {
      _logNotificationError('Failed to show task reminder', error, stackTrace);
    }
  }

  Future<void> _scheduleTaskReminder(Task task, {Project? project}) async {
    final reminder = task.reminder;
    if (reminder == null || !reminder.isAfter(DateTime.now())) {
      return;
    }

    final notificationId = _notificationIdForTask(task.id);
    await _plugin.zonedSchedule(
      id: notificationId,
      title: 'リマインダー',
      body: _notificationBody(task, project: project),
      scheduledDate: timezone.TZDateTime.from(reminder, timezone.local),
      notificationDetails: _notificationDetails(project: project),
      androidScheduleMode: _androidScheduleMode,
      payload: _payloadForTask(task.id),
    );
    _scheduledReminderIds.add(notificationId);
  }

  Future<void> _cancelPreviouslyScheduledReminders(List<Task> nextTasks) async {
    final idsToCancel = <int>{
      ..._scheduledReminderIds,
      for (final task in nextTasks) _notificationIdForTask(task.id),
    };

    try {
      final pendingRequests = await _plugin.pendingNotificationRequests();
      for (final request in pendingRequests) {
        final isTaskReminder = _taskIdFromPayload(request.payload) != null;
        if (isTaskReminder || defaultTargetPlatform == TargetPlatform.windows) {
          idsToCancel.add(request.id);
        }
      }
    } catch (_) {
      // Some platform implementations do not expose pending requests.
    }

    _scheduledReminderIds.clear();
    for (final id in idsToCancel) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> _captureLaunchNotification() async {
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp != true) {
      return;
    }

    final taskId = _taskIdFromPayload(
      launchDetails?.notificationResponse?.payload,
    );
    if (taskId != null) {
      _dispatchTaskSelection(taskId);
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final taskId = _taskIdFromPayload(response.payload);
    if (taskId != null) {
      _dispatchTaskSelection(taskId);
    }
  }

  void _dispatchTaskSelection(String taskId) {
    final handler = _onTaskSelected;
    if (handler == null) {
      _pendingTaskId = taskId;
      return;
    }

    handler(taskId);
  }

  Future<void> _configureLocalTimeZone() async {
    timezone_data.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      timezone.setLocalLocation(timezone.getLocation(timeZoneInfo.identifier));
    } catch (_) {
      timezone.setLocalLocation(timezone.getLocation('Etc/UTC'));
    }
  }
}

void _logNotificationError(
  String message,
  Object error,
  StackTrace stackTrace,
) {
  if (!kDebugMode) {
    return;
  }

  debugPrint('$message: $error');
  debugPrintStack(stackTrace: stackTrace);
}

NotificationDetails _notificationDetails({Project? project}) {
  final projectName = project?.name.trim();
  final subtitle = projectName == null || projectName.isEmpty
      ? null
      : projectName;

  return NotificationDetails(
    android: const AndroidNotificationDetails(
      _taskReminderChannelId,
      _taskReminderChannelName,
      channelDescription: 'タスクのリマインダー通知',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      ticker: 'タスクリマインダー',
    ),
    iOS: DarwinNotificationDetails(
      subtitle: subtitle,
      threadIdentifier: _taskReminderChannelId,
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
    macOS: DarwinNotificationDetails(
      subtitle: subtitle,
      threadIdentifier: _taskReminderChannelId,
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
    linux: const LinuxNotificationDetails(
      defaultActionName: '開く',
      urgency: LinuxNotificationUrgency.normal,
    ),
    windows: WindowsNotificationDetails(
      subtitle: subtitle,
      duration: WindowsNotificationDuration.long,
    ),
  );
}

String _notificationBody(Task task, {Project? project}) {
  final parts = <String>[
    task.title.trim().isEmpty ? '無題のタスク' : task.title.trim(),
  ];
  final projectName = project?.name.trim();
  final reminder = task.reminder;

  if (projectName != null && projectName.isNotEmpty) {
    parts.add(projectName);
  }
  if (reminder != null) {
    parts.add(_notificationTimeFormat.format(reminder));
  }

  return parts.join(' / ');
}

String _payloadForTask(String taskId) {
  return '$_taskNotificationPayloadPrefix$taskId';
}

String? _taskIdFromPayload(String? payload) {
  if (payload == null || !payload.startsWith(_taskNotificationPayloadPrefix)) {
    return null;
  }

  final taskId = payload.substring(_taskNotificationPayloadPrefix.length);
  return taskId.trim().isEmpty ? null : taskId;
}

int _notificationIdForTask(String taskId) {
  var hash = 0x811c9dc5;

  for (final codeUnit in taskId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }

  return hash == 0 ? 1 : hash;
}
