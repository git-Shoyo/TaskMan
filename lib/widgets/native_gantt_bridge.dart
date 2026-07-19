import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';

class NativeGanttBridge extends StatefulWidget {
  const NativeGanttBridge({
    super.key,
    required this.child,
    this.projectRepository,
    this.taskRepository,
  });

  final Widget child;
  final ProjectRepository? projectRepository;
  final TaskRepository? taskRepository;

  @override
  State<NativeGanttBridge> createState() => _NativeGanttBridgeState();
}

class _NativeGanttBridgeState extends State<NativeGanttBridge> {
  static const _windowChannel = MethodChannel('taskman/window');

  StreamSubscription<List<Project>>? _projectsSubscription;
  StreamSubscription<List<Task>>? _tasksSubscription;
  String? _memberId;
  List<String> _projectIds = const [];

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();

    if (!_isSupportedPlatform) {
      return;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isSupportedPlatform) {
      return;
    }

    _syncSubscriptions();
  }

  @override
  void didUpdateWidget(covariant NativeGanttBridge oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.projectRepository != widget.projectRepository ||
        oldWidget.taskRepository != widget.taskRepository) {
      _memberId = null;
      _projectIds = const [];
      _syncSubscriptions();
    }
  }

  @override
  void dispose() {
    unawaited(_projectsSubscription?.cancel());
    unawaited(_tasksSubscription?.cancel());
    super.dispose();
  }

  void _syncSubscriptions() {
    final auth = AuthScope.maybeOf(context);
    final nextMemberId =
        auth != null && auth.isSignedIn && !auth.needsEmailVerification
        ? auth.currentUser.id
        : null;

    if (_memberId == nextMemberId) {
      return;
    }

    _memberId = nextMemberId;
    _projectIds = const [];
    unawaited(_projectsSubscription?.cancel());
    unawaited(_tasksSubscription?.cancel());
    _projectsSubscription = null;
    _tasksSubscription = null;

    if (nextMemberId == null) {
      unawaited(_sendTasks(const <Task>[]));
      return;
    }

    _projectsSubscription = (widget.projectRepository ?? ProjectRepository())
        .watchProjects(memberId: nextMemberId)
        .listen(
          _watchProjectTasks,
          onError: (_) => unawaited(_sendTasks(const <Task>[])),
        );
  }

  void _watchProjectTasks(List<Project> projects) {
    final nextProjectIds = projects.map((project) => project.id).toList();

    if (listEquals(_projectIds, nextProjectIds)) {
      return;
    }

    _projectIds = nextProjectIds;
    unawaited(_tasksSubscription?.cancel());
    _tasksSubscription = null;

    if (nextProjectIds.isEmpty) {
      unawaited(_sendTasks(const <Task>[]));
      return;
    }

    _tasksSubscription = (widget.taskRepository ?? TaskRepository())
        .watchTasks(projectIds: nextProjectIds)
        .listen((tasks) {
          unawaited(_sendTasks(tasks));
        }, onError: (_) => unawaited(_sendTasks(const <Task>[])));
  }

  Future<void> _sendTasks(List<Task> tasks) async {
    final payload = _nativeGanttPayload(tasks);
    try {
      await _windowChannel.invokeMethod<void>(
        'updateNativeGanttTasks',
        payload,
      );
    } on MissingPluginException {
      // The native gantt is optional, so unsupported platforms and tests should
      // never disturb the main app.
    } on PlatformException {
      // Native gantt is an auxiliary surface; the main app should keep running.
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

List<Map<String, Object?>> _nativeGanttPayload(List<Task> tasks) {
  final today = DateUtils.dateOnly(DateTime.now());
  final range = _GanttRange(
    start: today,
    end: today.add(const Duration(days: 6)),
  );

  return _visibleTasks(tasks, range).take(6).map((task) {
    final taskRange = _taskRange(task)!;
    final assigneeName = task.assigneeName?.trim() ?? '';

    return <String, Object?>{
      'id': task.id,
      'title': task.title.trim().isEmpty ? '無題のタスク' : task.title.trim(),
      'label': assigneeName.isEmpty
          ? '${task.completionPercent}%'
          : assigneeName,
      'startOffset': _dayOffset(range.start, taskRange.start).clamp(0, 6),
      'endOffset': _dayOffset(range.start, taskRange.end).clamp(0, 6),
      'startEpochDay': _epochDay(taskRange.start),
      'endEpochDay': _epochDay(taskRange.end),
      'deadlineEpochDay': task.deadline == null
          ? null
          : _epochDay(task.deadline!),
      'completionPercent': task.completionPercent,
      'priority': task.priority ?? 0,
      'isDone': task.isDone,
      'isOverdue': _isOverdue(task),
    };
  }).toList();
}

class _GanttRange {
  const _GanttRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool overlaps(_GanttRange other) {
    return !other.end.isBefore(start) && !other.start.isAfter(end);
  }
}

List<Task> _visibleTasks(List<Task> tasks, _GanttRange range) {
  final visibleTasks = tasks.where((task) {
    final taskRange = _taskRange(task);
    return taskRange != null && range.overlaps(taskRange);
  }).toList();

  visibleTasks.sort((a, b) {
    if (a.isDone != b.isDone) {
      return a.isDone ? 1 : -1;
    }

    final aRange = _taskRange(a)!;
    final bRange = _taskRange(b)!;
    final startCompare = aRange.start.compareTo(bRange.start);
    if (startCompare != 0) {
      return startCompare;
    }

    return (b.priority ?? 0).compareTo(a.priority ?? 0);
  });

  return visibleTasks;
}

_GanttRange? _taskRange(Task task) {
  final rawStart = task.startDate ?? task.deadline;
  final rawEnd = task.deadline ?? task.startDate;

  if (rawStart == null || rawEnd == null) {
    return null;
  }

  final start = DateUtils.dateOnly(rawStart);
  final end = DateUtils.dateOnly(rawEnd);

  return _GanttRange(
    start: end.isBefore(start) ? end : start,
    end: end.isBefore(start) ? start : end,
  );
}

int _dayOffset(DateTime start, DateTime date) {
  return DateUtils.dateOnly(date).difference(DateUtils.dateOnly(start)).inDays;
}

int _epochDay(DateTime date) {
  final day = DateUtils.dateOnly(date);
  return day.difference(DateTime(1970)).inDays;
}

bool _isOverdue(Task task) {
  final deadline = task.deadline;

  if (task.isDone || deadline == null) {
    return false;
  }

  return DateUtils.dateOnly(
    deadline,
  ).isBefore(DateUtils.dateOnly(DateTime.now()));
}
