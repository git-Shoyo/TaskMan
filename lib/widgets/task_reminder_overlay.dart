import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/screens/task_detail_screen.dart';
import 'package:taskman/services/task_notification_service.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';
import 'package:taskman/systems/task_reminder.dart';

final DateFormat _reminderDateTimeFormat = DateFormat('yyyy/MM/dd HH:mm');
final DateFormat _reminderTimeFormat = DateFormat('HH:mm');

class TaskReminderOverlay extends StatefulWidget {
  const TaskReminderOverlay({
    super.key,
    required this.child,
    this.projectRepository,
    this.taskRepository,
  });

  final Widget child;
  final ProjectRepository? projectRepository;
  final TaskRepository? taskRepository;

  @override
  State<TaskReminderOverlay> createState() => _TaskReminderOverlayState();
}

class _TaskReminderOverlayState extends State<TaskReminderOverlay>
    with WidgetsBindingObserver {
  static const _animationDuration = Duration(milliseconds: 280);
  static const _displayDuration = Duration(seconds: 7);
  static const _maximumReminderCheckDelay = Duration(hours: 1);
  static const _fallbackReminderCheckInterval = Duration(seconds: 15);

  late final ProjectRepository _projectRepository;
  late final TaskRepository _taskRepository;

  final _shownReminderKeys = <String>{};
  final _pendingToasts = Queue<_TaskReminderToast>();

  StreamSubscription<List<Project>>? _projectSubscription;
  StreamSubscription<List<Task>>? _taskSubscription;
  Timer? _reminderTimer;
  Timer? _fallbackReminderTimer;
  Timer? _autoDismissTimer;
  Timer? _removeToastTimer;

  String? _memberId;
  String? _projectIdsSignature;
  List<Project> _projects = const [];
  List<Task> _tasks = const [];
  _TaskReminderToast? _currentToast;
  bool _isToastVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _projectRepository = widget.projectRepository ?? ProjectRepository();
    _taskRepository = widget.taskRepository ?? TaskRepository();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final memberId = AuthScope.of(context).currentUser.id;
    if (_memberId == memberId) {
      return;
    }

    _memberId = memberId;
    _shownReminderKeys.clear();
    _pendingToasts.clear();
    _currentToast = null;
    _isToastVisible = false;
    _projectIdsSignature = null;
    _subscribeProjects(memberId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_projectSubscription?.cancel());
    unawaited(_taskSubscription?.cancel());
    _reminderTimer?.cancel();
    _fallbackReminderTimer?.cancel();
    _autoDismissTimer?.cancel();
    _removeToastTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkReminders();
      _startFallbackReminderChecks();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _fallbackReminderTimer?.cancel();
      _fallbackReminderTimer = null;
    }
  }

  void _subscribeProjects(String memberId) {
    unawaited(_projectSubscription?.cancel());
    unawaited(_taskSubscription?.cancel());
    _projectSubscription = _projectRepository
        .watchProjects(memberId: memberId)
        .listen(_handleProjects, onError: (_) => _clearWatchedTasks());
  }

  void _handleProjects(List<Project> projects) {
    if (!mounted) {
      return;
    }

    _projects = projects;

    final projectIds = projects.map((project) => project.id).toList();
    final signature = projectIds.join('|');
    if (_projectIdsSignature == signature) {
      _queueDueReminders();
      return;
    }

    _projectIdsSignature = signature;
    unawaited(_taskSubscription?.cancel());
    _taskSubscription = _taskRepository
        .watchTasks(projectIds: projectIds)
        .listen(_handleTasks, onError: (_) => _clearWatchedTasks());
  }

  void _handleTasks(List<Task> tasks) {
    if (!mounted) {
      return;
    }

    _tasks = tasks;
    unawaited(
      TaskNotificationService.instance.syncTaskReminders(
        tasks,
        projectById: {for (final project in _projects) project.id: project},
      ),
    );
    _checkReminders();
    _startFallbackReminderChecks();
  }

  void _clearWatchedTasks() {
    unawaited(_taskSubscription?.cancel());
    _taskSubscription = null;
    _projectIdsSignature = null;
    _tasks = const [];
    _pendingToasts.clear();
    _reminderTimer?.cancel();
    _fallbackReminderTimer?.cancel();
    _fallbackReminderTimer = null;
  }

  void _checkReminders() {
    if (!mounted || _tasks.isEmpty) {
      return;
    }

    _queueDueReminders();
    _scheduleNextReminderCheck();
  }

  void _queueDueReminders() {
    final projectById = {for (final project in _projects) project.id: project};
    final dueTasks = dueTaskReminders(
      _tasks,
      now: DateTime.now(),
      ignoredKeys: _shownReminderKeys,
    );

    for (final task in dueTasks) {
      final key = taskReminderKey(task);
      final project = projectById[task.projectId];
      if (_pendingToasts.any((toast) => toast.key == key) ||
          _currentToast?.key == key) {
        continue;
      }

      _shownReminderKeys.add(key);
      unawaited(
        TaskNotificationService.instance.showTaskReminderNowForDueTimeFallback(
          task,
          project: project,
        ),
      );
      _pendingToasts.add(
        _TaskReminderToast(
          key: key,
          task: task,
          reminder: task.reminder!,
          project: project,
        ),
      );
    }

    _showNextToastIfIdle();
  }

  void _scheduleNextReminderCheck() {
    _reminderTimer?.cancel();

    final now = DateTime.now();
    final nextReminder = nextTaskReminderTime(
      _tasks,
      now: now,
      ignoredKeys: _shownReminderKeys,
    );
    if (nextReminder == null) {
      return;
    }

    var delay = nextReminder.difference(now);
    if (delay < Duration.zero) {
      delay = Duration.zero;
    } else if (delay > _maximumReminderCheckDelay) {
      delay = _maximumReminderCheckDelay;
    }

    _reminderTimer = Timer(delay, _checkReminders);
  }

  void _startFallbackReminderChecks() {
    if (_fallbackReminderTimer != null || _tasks.isEmpty) {
      return;
    }

    _fallbackReminderTimer = Timer.periodic(
      _fallbackReminderCheckInterval,
      (_) => _checkReminders(),
    );
  }

  void _showNextToastIfIdle() {
    if (!mounted || _currentToast != null || _pendingToasts.isEmpty) {
      return;
    }

    _removeToastTimer?.cancel();
    _autoDismissTimer?.cancel();

    setState(() {
      _currentToast = _pendingToasts.removeFirst();
      _isToastVisible = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentToast == null) {
        return;
      }

      setState(() {
        _isToastVisible = true;
      });
      _autoDismissTimer = Timer(_displayDuration, _dismissCurrentToast);
    });
  }

  void _dismissCurrentToast() {
    if (!mounted || _currentToast == null) {
      return;
    }

    _autoDismissTimer?.cancel();
    _removeToastTimer?.cancel();

    setState(() {
      _isToastVisible = false;
    });

    _removeToastTimer = Timer(_animationDuration, () {
      if (!mounted) {
        return;
      }

      setState(() {
        _currentToast = null;
      });
      _showNextToastIfIdle();
    });
  }

  void _openCurrentToast() {
    final toast = _currentToast;
    if (toast == null) {
      return;
    }

    _dismissCurrentToast();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            TaskDetailScreen(taskId: toast.task.id, project: toast.project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toast = _currentToast;
    final mediaQuery = MediaQuery.of(context);
    final entersFromRight = _entersFromRight(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (toast != null)
          Positioned(
            top: mediaQuery.padding.top + 12,
            left: entersFromRight ? null : 12,
            right: 12,
            child: Align(
              alignment: entersFromRight
                  ? Alignment.topRight
                  : Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: entersFromRight ? 380 : mediaQuery.size.width - 24,
                ),
                child: AnimatedSlide(
                  duration: _animationDuration,
                  curve: Curves.easeOutCubic,
                  offset: _isToastVisible
                      ? Offset.zero
                      : entersFromRight
                      ? const Offset(1.1, 0)
                      : const Offset(0, -1.15),
                  child: AnimatedOpacity(
                    duration: _animationDuration,
                    curve: Curves.easeOutCubic,
                    opacity: _isToastVisible ? 1 : 0,
                    child: _TaskReminderToastCard(
                      toast: toast,
                      onOpen: _openCurrentToast,
                      onDismiss: _dismissCurrentToast,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskReminderToast {
  const _TaskReminderToast({
    required this.key,
    required this.task,
    required this.reminder,
    required this.project,
  });

  final String key;
  final Task task;
  final DateTime reminder;
  final Project? project;
}

class _TaskReminderToastCard extends StatelessWidget {
  const _TaskReminderToastCard({
    required this.toast,
    required this.onOpen,
    required this.onDismiss,
  });

  final _TaskReminderToast toast;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final projectName = toast.project?.name.trim();
    final meta = [
      if (projectName != null && projectName.isNotEmpty) projectName,
      _formatReminderTime(toast.reminder),
    ].join(' / ');

    return Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.notifications_active,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'リマインダー',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toast.task.title.isEmpty ? '無題のタスク' : toast.task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '閉じる',
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _entersFromRight(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.windows ||
      MediaQuery.sizeOf(context).width >= 800;
}

String _formatReminderTime(DateTime reminder) {
  final now = DateTime.now();
  if (DateUtils.isSameDay(now, reminder)) {
    return '今日 ${_reminderTimeFormat.format(reminder)}';
  }

  return _reminderDateTimeFormat.format(reminder);
}
