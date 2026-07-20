import 'package:flutter/material.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';
import 'package:taskman/widgets/task_assignee_labels.dart';

class SevenDayGantt extends StatelessWidget {
  SevenDayGantt({
    super.key,
    TaskRepository? taskRepository,
    UserRepository? userRepository,
    this.projectIds,
    this.compact = false,
    this.frameless = false,
    this.maxRows = 8,
    this.onOpenTask,
  }) : taskRepository = taskRepository ?? TaskRepository(),
       userRepository = userRepository ?? UserRepository();

  final TaskRepository taskRepository;
  final UserRepository userRepository;
  final Iterable<String>? projectIds;
  final bool compact;
  final bool frameless;
  final int maxRows;
  final ValueChanged<Task>? onOpenTask;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
      stream: taskRepository.watchTasks(projectIds: projectIds),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GanttShell(
            compact: compact,
            frameless: frameless,
            child: const _GanttMessage(text: 'タスクの読み込みに失敗しました'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _GanttShell(
            compact: compact,
            frameless: frameless,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final today = DateUtils.dateOnly(DateTime.now());
        final range = _GanttRange(
          start: today,
          end: today.add(const Duration(days: 6)),
        );
        final tasks = _visibleTasks(
          snapshot.data ?? const <Task>[],
          range,
        ).take(maxRows).toList();

        return TaskAssigneeLabelsBuilder(
          tasks: tasks,
          userRepository: userRepository,
          builder: (context, assigneeLabels) {
            return _GanttShell(
              compact: compact,
              frameless: frameless,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GanttHeader(compact: compact, range: range),
                  const SizedBox(height: 10),
                  if (tasks.isEmpty)
                    const Expanded(
                      child: _GanttMessage(text: '7日以内のタスクはありません'),
                    )
                  else
                    Expanded(
                      child: _GanttRows(
                        compact: compact,
                        tasks: tasks,
                        assigneeLabels: assigneeLabels,
                        range: range,
                        onOpenTask: onOpenTask,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class UserSevenDayGantt extends StatelessWidget {
  UserSevenDayGantt({
    super.key,
    ProjectRepository? projectRepository,
    TaskRepository? taskRepository,
    UserRepository? userRepository,
    this.compact = false,
    this.frameless = false,
    this.maxRows = 8,
    this.onOpenTask,
  }) : projectRepository = projectRepository ?? ProjectRepository(),
       taskRepository = taskRepository ?? TaskRepository(),
       userRepository = userRepository ?? UserRepository();

  final ProjectRepository projectRepository;
  final TaskRepository taskRepository;
  final UserRepository userRepository;
  final bool compact;
  final bool frameless;
  final int maxRows;
  final ValueChanged<Task>? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.maybeOf(context);

    if (auth == null || !auth.isSignedIn) {
      return _GanttShell(
        compact: compact,
        frameless: frameless,
        child: const _GanttMessage(text: 'ログインするとタスクを表示します'),
      );
    }

    if (auth.needsEmailVerification) {
      return _GanttShell(
        compact: compact,
        frameless: frameless,
        child: const _GanttMessage(text: 'メール確認後にタスクを表示します'),
      );
    }

    return StreamBuilder<List<Project>>(
      stream: projectRepository.watchProjects(memberId: auth.currentUser.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GanttShell(
            compact: compact,
            frameless: frameless,
            child: const _GanttMessage(text: 'プロジェクトの読み込みに失敗しました'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _GanttShell(
            compact: compact,
            frameless: frameless,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        return SevenDayGantt(
          taskRepository: taskRepository,
          userRepository: userRepository,
          projectIds: (snapshot.data ?? const <Project>[]).map(
            (project) => project.id,
          ),
          compact: compact,
          frameless: frameless,
          maxRows: maxRows,
          onOpenTask: onOpenTask,
        );
      },
    );
  }
}

class _GanttShell extends StatelessWidget {
  const _GanttShell({
    required this.compact,
    required this.frameless,
    required this.child,
  });

  final bool compact;
  final bool frameless;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final padding = compact ? 12.0 : 16.0;

    if (frameless) {
      return SizedBox.expand(
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: child,
    );
  }
}

class _GanttHeader extends StatelessWidget {
  const _GanttHeader({required this.compact, required this.range});

  final bool compact;
  final _GanttRange range;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(Icons.stacked_bar_chart, size: compact ? 18 : 20),
        const Spacer(),
        Text(
          '${_formatShortDate(range.start)} - ${_formatShortDate(range.end)}',
          style: textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _GanttRows extends StatelessWidget {
  const _GanttRows({
    required this.compact,
    required this.tasks,
    required this.assigneeLabels,
    required this.range,
    required this.onOpenTask,
  });

  final bool compact;
  final List<Task> tasks;
  final Map<String, String> assigneeLabels;
  final _GanttRange range;
  final ValueChanged<Task>? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final rowHeight = compact ? 30.0 : 36.0;

    return Column(
      children: [
        _DayHeader(compact: compact),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: tasks.length,
            separatorBuilder: (context, index) =>
                SizedBox(height: compact ? 5 : 7),
            itemBuilder: (context, index) {
              return SizedBox(
                height: rowHeight,
                child: _TaskGanttRow(
                  compact: compact,
                  task: tasks[index],
                  assigneeLabels: assigneeLabels,
                  range: range,
                  onOpenTask: onOpenTask,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final labelWidth = compact ? 92.0 : 128.0;
    final textStyle = Theme.of(context).textTheme.labelSmall;

    return Row(
      children: [
        SizedBox(width: labelWidth),
        Expanded(
          child: Row(
            children: [
              for (var index = 0; index < 7; index += 1)
                Expanded(
                  child: Text(
                    _formatDayLabel(today.add(Duration(days: index))),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskGanttRow extends StatelessWidget {
  const _TaskGanttRow({
    required this.compact,
    required this.task,
    required this.assigneeLabels,
    required this.range,
    required this.onOpenTask,
  });

  final bool compact;
  final Task task;
  final Map<String, String> assigneeLabels;
  final _GanttRange range;
  final ValueChanged<Task>? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final labelWidth = compact ? 92.0 : 128.0;
    final taskRange = _taskRange(task)!;

    final row = Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            task.title.isEmpty ? '無題のタスク' : task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final startIndex = _dayOffset(
                range.start,
                taskRange.start,
              ).clamp(0, 6);
              final endIndex = _dayOffset(
                range.start,
                taskRange.end,
              ).clamp(0, 6);
              final cellWidth = constraints.maxWidth / 7;
              final left = startIndex * cellWidth;
              final width = (endIndex - startIndex + 1) * cellWidth;

              return Stack(
                children: [
                  const _GanttGrid(),
                  Positioned(
                    left: left + 2,
                    top: compact ? 5 : 6,
                    width: (width - 4).clamp(8.0, constraints.maxWidth),
                    height: compact ? 20 : 24,
                    child: _TaskBar(
                      task: task,
                      assigneeLabels: assigneeLabels,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );

    if (onOpenTask == null) {
      return row;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpenTask!(task),
        child: row,
      ),
    );
  }
}

class _GanttGrid extends StatelessWidget {
  const _GanttGrid();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;

    return Row(
      children: [
        for (var index = 0; index < 7; index += 1)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: index == 0 ? BorderSide(color: color) : BorderSide.none,
                  right: BorderSide(color: color),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskBar extends StatelessWidget {
  const _TaskBar({required this.task, required this.assigneeLabels});

  final Task task;
  final Map<String, String> assigneeLabels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _taskColor(colorScheme, task);
    final assigneeLabel = taskAssigneeLabel(task, assigneeLabels);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            assigneeLabel.isNotEmpty
                ? assigneeLabel
                : '${task.completionPercent}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _onTaskColor(colorScheme, task),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GanttMessage extends StatelessWidget {
  const _GanttMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
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

Color _taskColor(ColorScheme colorScheme, Task task) {
  if (task.isDone) {
    return colorScheme.secondary;
  }

  if (_isOverdue(task)) {
    return colorScheme.error;
  }

  if ((task.priority ?? 0) >= 4) {
    return colorScheme.tertiary;
  }

  return colorScheme.primary;
}

Color _onTaskColor(ColorScheme colorScheme, Task task) {
  if (task.isDone) {
    return colorScheme.onSecondary;
  }

  if (_isOverdue(task)) {
    return colorScheme.onError;
  }

  if ((task.priority ?? 0) >= 4) {
    return colorScheme.onTertiary;
  }

  return colorScheme.onPrimary;
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

String _formatShortDate(DateTime date) {
  return '${date.month}/${date.day}';
}

String _formatDayLabel(DateTime date) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${date.day} ${weekdays[date.weekday - 1]}';
}
