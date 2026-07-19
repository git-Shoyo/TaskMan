import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/screens/add_project/add_project_screen.dart';
import 'package:taskman/screens/add_task/add_task_screen.dart';
import 'package:taskman/screens/project_screen.dart';
import 'package:taskman/screens/task_detail_screen.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';
import 'package:taskman/widgets/seven_day_gantt.dart';

final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
final DateFormat _dateTimeFormat = DateFormat('yyyy/MM/dd HH:mm');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final projectRepository = ProjectRepository();
  final taskRepository = TaskRepository();

  void _openProject(Project project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailScreen(project: project),
      ),
    );
  }

  void _openTask(Task task, Map<String, Project> projectById) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskDetailScreen(
          taskId: task.id,
          project: projectById[task.projectId],
        ),
      ),
    );
  }

  void _openAddProject() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddProjectScreen()),
    );
  }

  Future<void> _openAddTask(List<Project> projects) async {
    if (projects.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にプロジェクトを作成してください')));
      return;
    }

    Project? selectedProject;
    final sortedProjects = [...projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (projects.length == 1) {
      selectedProject = projects.first;
    } else {
      selectedProject = await showModalBottomSheet<Project>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: sortedProjects.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final project = sortedProjects[index];

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder),
                  title: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '更新 ${_dateTimeFormat.format(project.updatedAt)}',
                  ),
                  onTap: () => Navigator.pop(context, project),
                );
              },
            ),
          );
        },
      );
    }

    if (!mounted || selectedProject == null) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskScreen(project: selectedProject!),
      ),
    );
  }

  void _openNotification(
    _HomeNotification notification,
    Map<String, Project> projectById,
  ) {
    switch (notification.kind) {
      case _NotificationKind.appUpdate:
        _showAppUpdateNotice(notification);
        return;
      case _NotificationKind.newTask:
      case _NotificationKind.taskAssignment:
      case _NotificationKind.taskDeadline:
        final task = notification.task;
        if (task == null) {
          _showMissingNotificationTarget();
          return;
        }
        _openTask(task, projectById);
        return;
      case _NotificationKind.projectInvite:
        final project = notification.project;
        if (project == null) {
          _showMissingNotificationTarget();
          return;
        }
        _openProject(project);
        return;
    }
  }

  Future<void> _showAppUpdateNotice(_HomeNotification notification) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.system_update_alt),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notification.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Text(notification.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openNotificationHistory(
    List<_HomeNotification> notifications,
    Map<String, Project> projectById,
  ) async {
    final selectedNotification = await Navigator.push<_HomeNotification>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            _NotificationHistoryScreen(notifications: notifications),
      ),
    );

    if (!mounted || selectedNotification == null) {
      return;
    }

    _openNotification(selectedNotification, projectById);
  }

  void _showMissingNotificationTarget() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('通知先のデータが見つかりません')));
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.of(context).currentUser;

    return StreamBuilder<List<Project>>(
      stream: projectRepository.watchProjects(memberId: currentUser.id),
      builder: (context, projectSnapshot) {
        final projects = projectSnapshot.data ?? const <Project>[];
        final projectIds = projects.map((project) => project.id);

        return StreamBuilder<List<Task>>(
          stream: taskRepository.watchTasks(projectIds: projectIds),
          builder: (context, taskSnapshot) {
            final tasks = taskSnapshot.data ?? const <Task>[];
            final projectById = {
              for (final project in projects) project.id: project,
            };

            return SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showNotificationsAtSide = constraints.maxWidth >= 980;
                  final mainContentWidth = showNotificationsAtSide
                      ? constraints.maxWidth - 336
                      : constraints.maxWidth;
                  final isWide = mainContentWidth >= 760;
                  final isLoadingProjects =
                      projectSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !projectSnapshot.hasData;
                  final isLoadingTasks =
                      taskSnapshot.connectionState == ConnectionState.waiting &&
                      !taskSnapshot.hasData;
                  final hasProjectError = projectSnapshot.hasError;
                  final hasTaskError = taskSnapshot.hasError;
                  final overdueTasks = _overdueTasks(tasks);
                  final todayTasks = _todayFocusTasks(tasks);
                  final highPriorityTasks = _highPriorityTasks(tasks);
                  final recentlyCommentedTasks = _recentlyCommentedTasks(tasks);
                  final projectProgress = _projectProgress(projects, tasks);
                  final notifications = _homeNotifications(
                    projects: projects,
                    tasks: tasks,
                  );
                  final notificationHistory = _notificationHistory(
                    projects: projects,
                    tasks: tasks,
                  );
                  final notificationPanel = _NotificationPanel(
                    notifications: notifications,
                    isLoading: isLoadingProjects || isLoadingTasks,
                    hasError: hasProjectError || hasTaskError,
                    onOpenNotification: (notification) =>
                        _openNotification(notification, projectById),
                    onOpenHistory: () => _openNotificationHistory(
                      notificationHistory,
                      projectById,
                    ),
                  );
                  final mainContent = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProgressSummary(
                        tasks: tasks,
                        isLoading: isLoadingTasks,
                        hasError: hasTaskError,
                      ),
                      const SizedBox(height: 16),
                      _TodayFocusPanel(
                        tasks: todayTasks,
                        projectById: projectById,
                        isLoading: isLoadingTasks,
                        hasError: hasTaskError,
                        onOpenTask: (task) => _openTask(task, projectById),
                      ),
                      const SizedBox(height: 16),
                      _PriorityTaskPanel(
                        tasks: highPriorityTasks,
                        projectById: projectById,
                        isLoading: isLoadingTasks,
                        hasError: hasTaskError,
                        onOpenTask: (task) => _openTask(task, projectById),
                      ),
                      const SizedBox(height: 16),
                      _RecentCommentsPanel(
                        commentedTasks: recentlyCommentedTasks,
                        isLoading: isLoadingTasks,
                        hasError: hasTaskError,
                        onOpenTask: (task) => _openTask(task, projectById),
                      ),
                      const SizedBox(height: 16),
                      _ProjectProgressPanel(
                        progress: projectProgress,
                        isLoading: isLoadingProjects || isLoadingTasks,
                        hasError: hasProjectError || hasTaskError,
                        onOpenProject: _openProject,
                      ),
                      const SizedBox(height: 16),
                      _QuickAccess(
                        projects: _recentProjects(projects),
                        tasks: _recentTasks(tasks),
                        projectById: projectById,
                        isWide: isWide,
                        isLoadingProjects: isLoadingProjects,
                        isLoadingTasks: isLoadingTasks,
                        hasProjectError: hasProjectError,
                        hasTaskError: hasTaskError,
                        onOpenProject: _openProject,
                        onOpenTask: (task) => _openTask(task, projectById),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.event_note, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '予定',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 280,
                        child: SevenDayGantt(
                          projectIds: projectIds,
                          compact: true,
                          maxRows: 6,
                          onOpenTask: (task) => _openTask(task, projectById),
                        ),
                      ),
                    ],
                  );

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _HomeHeader(
                        onAddTask: () => _openAddTask(projects),
                        onAddProject: _openAddProject,
                      ),
                      const SizedBox(height: 16),
                      if (overdueTasks.isNotEmpty) ...[
                        _OverdueWarning(
                          tasks: overdueTasks,
                          onOpenTask: (task) => _openTask(task, projectById),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (showNotificationsAtSide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: mainContent),
                            const SizedBox(width: 16),
                            SizedBox(width: 320, child: notificationPanel),
                          ],
                        )
                      else ...[
                        mainContent,
                        const SizedBox(height: 16),
                        notificationPanel,
                      ],
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onAddTask, required this.onAddProject});

  final VoidCallback onAddTask;
  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final title = Text('ホーム', style: Theme.of(context).textTheme.headlineSmall);
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.icon(
          onPressed: onAddTask,
          icon: const Icon(Icons.add_task),
          label: const Text('タスク追加'),
        ),
        FilledButton.tonalIcon(
          onPressed: onAddProject,
          icon: const Icon(Icons.create_new_folder),
          label: const Text('プロジェクト作成'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              actions,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 12), actions],
        );
      },
    );
  }
}

class _OverdueWarning extends StatelessWidget {
  const _OverdueWarning({required this.tasks, required this.onOpenTask});

  final List<Task> tasks;
  final ValueChanged<Task> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sampleTasks = tasks.take(2).map(_taskTitle).join(' / ');
    final extraCount = tasks.length > 2 ? ' ほか${tasks.length - 2}件' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '期限切れタスクが${tasks.length}件あります',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$sampleTasks$extraCount',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => onOpenTask(tasks.first),
              icon: const Icon(Icons.open_in_new),
              label: const Text('確認'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({
    required this.tasks,
    required this.isLoading,
    required this.hasError,
  });

  final List<Task> tasks;
  final bool isLoading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final doneCount = tasks.where((task) => task.isDone).length;
    final activeCount = tasks.length - doneCount;
    final overdueCount = tasks
        .where((task) => _isTaskOverdue(task, today))
        .length;
    final dueTodayCount = tasks
        .where((task) => _isTaskDueToday(task, today))
        .length;
    final displayValue = hasError
        ? '!'
        : isLoading
        ? '-'
        : null;
    final items = [
      _SummaryItem(
        icon: Icons.all_inbox,
        label: '全タスク',
        value: displayValue ?? '${tasks.length}',
      ),
      _SummaryItem(
        icon: Icons.check_circle_outline,
        label: '完了',
        value: displayValue ?? '$doneCount',
      ),
      _SummaryItem(
        icon: Icons.pending_actions,
        label: '未完了',
        value: displayValue ?? '$activeCount',
      ),
      _SummaryItem(
        icon: Icons.error_outline,
        label: '期限切れ',
        value: displayValue ?? '$overdueCount',
        isDanger: overdueCount > 0 && !hasError && !isLoading,
      ),
      _SummaryItem(
        icon: Icons.today,
        label: '今日期限',
        value: displayValue ?? '$dueTodayCount',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(icon: Icons.dashboard_outlined, title: '進捗サマリー'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760
                ? 5
                : constraints.maxWidth >= 520
                ? 3
                : 2;
            const gap = 8.0;
            final itemWidth =
                (constraints.maxWidth - (gap * (columns - 1))) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: _SummaryTile(item: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.item});

  final _SummaryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.isDanger ? colorScheme.error : colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 20, color: accent),
          const SizedBox(height: 8),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDanger;
}

class _TodayFocusPanel extends StatelessWidget {
  const _TodayFocusPanel({
    required this.tasks,
    required this.projectById,
    required this.isLoading,
    required this.hasError,
    required this.onOpenTask,
  });

  final List<Task> tasks;
  final Map<String, Project> projectById;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<Task> onOpenTask;

  @override
  Widget build(BuildContext context) {
    return _TaskDigestPanel(
      icon: Icons.today,
      title: '今日やること',
      isLoading: isLoading,
      hasError: hasError,
      emptyText: '今日対応するタスクはありません',
      children: [
        for (final task in tasks)
          _TaskDigestTile(
            task: task,
            subtitle: _taskTimingSubtitle(task, projectById),
            onTap: () => onOpenTask(task),
          ),
      ],
    );
  }
}

class _PriorityTaskPanel extends StatelessWidget {
  const _PriorityTaskPanel({
    required this.tasks,
    required this.projectById,
    required this.isLoading,
    required this.hasError,
    required this.onOpenTask,
  });

  final List<Task> tasks;
  final Map<String, Project> projectById;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<Task> onOpenTask;

  @override
  Widget build(BuildContext context) {
    return _TaskDigestPanel(
      icon: Icons.priority_high,
      title: '優先度の高いタスク',
      isLoading: isLoading,
      hasError: hasError,
      emptyText: '優先度の高い未完了タスクはありません',
      children: [
        for (final task in tasks)
          _TaskDigestTile(
            task: task,
            subtitle: _taskPrioritySubtitle(task, projectById),
            onTap: () => onOpenTask(task),
          ),
      ],
    );
  }
}

class _RecentCommentsPanel extends StatelessWidget {
  const _RecentCommentsPanel({
    required this.commentedTasks,
    required this.isLoading,
    required this.hasError,
    required this.onOpenTask,
  });

  final List<_CommentedTask> commentedTasks;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<Task> onOpenTask;

  @override
  Widget build(BuildContext context) {
    return _TaskDigestPanel(
      icon: Icons.forum_outlined,
      title: '最近コメントされたタスク',
      isLoading: isLoading,
      hasError: hasError,
      emptyText: '最近のコメントはありません',
      children: [
        for (final commentedTask in commentedTasks)
          _CommentDigestTile(
            commentedTask: commentedTask,
            onTap: () => onOpenTask(commentedTask.task),
          ),
      ],
    );
  }
}

class _TaskDigestPanel extends StatelessWidget {
  const _TaskDigestPanel({
    required this.icon,
    required this.title,
    required this.isLoading,
    required this.hasError,
    required this.emptyText,
    required this.children,
  });

  final IconData icon;
  final String title;
  final bool isLoading;
  final bool hasError;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(icon: icon, title: title, dense: true),
          const SizedBox(height: 10),
          if (hasError)
            const _PanelMessage(text: '読み込みに失敗しました')
          else if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (children.isEmpty)
            _PanelMessage(text: emptyText)
          else
            for (final child in children) ...[
              child,
              if (child != children.last) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _TaskDigestTile extends StatelessWidget {
  const _TaskDigestTile({
    required this.task,
    required this.subtitle,
    required this.onTap,
  });

  final Task task;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final iconColor = _isTaskOverdue(task, today)
        ? colorScheme.error
        : colorScheme.primary;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.radio_button_unchecked, size: 22, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _taskTitle(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentDigestTile extends StatelessWidget {
  const _CommentDigestTile({required this.commentedTask, required this.onTap});

  final _CommentedTask commentedTask;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final comment = commentedTask.comment;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.comment_outlined, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _taskTitle(commentedTask.task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${comment.authorName} / ${_formatNotificationTime(comment.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _commentSnippet(comment),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectProgressPanel extends StatelessWidget {
  const _ProjectProgressPanel({
    required this.progress,
    required this.isLoading,
    required this.hasError,
    required this.onOpenProject,
  });

  final List<_ProjectProgress> progress;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<Project> onOpenProject;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.folder_copy_outlined,
            title: 'プロジェクト別ミニ進捗',
            dense: true,
          ),
          const SizedBox(height: 10),
          if (hasError)
            const _PanelMessage(text: '読み込みに失敗しました')
          else if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (progress.isEmpty)
            const _PanelMessage(text: 'プロジェクトがありません')
          else
            for (final item in progress) ...[
              _ProjectProgressTile(
                progress: item,
                onTap: () => onOpenProject(item.project),
              ),
              if (item != progress.last) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _ProjectProgressTile extends StatelessWidget {
  const _ProjectProgressTile({required this.progress, required this.onTap});

  final _ProjectProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = (progress.ratio * 100).round();

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      progress.project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$percent%',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 8,
                  backgroundColor: colorScheme.surface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${progress.doneCount}/${progress.totalCount} 完了',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: dense ? 20 : 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: dense
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _CommentedTask {
  const _CommentedTask({required this.task, required this.comment});

  final Task task;
  final TaskComment comment;
}

class _ProjectProgress {
  const _ProjectProgress({
    required this.project,
    required this.doneCount,
    required this.totalCount,
  });

  final Project project;
  final int doneCount;
  final int totalCount;

  double get ratio {
    if (totalCount == 0) {
      return 0;
    }

    return doneCount / totalCount;
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.notifications,
    required this.isLoading,
    required this.hasError,
    required this.onOpenNotification,
    required this.onOpenHistory,
  });

  final List<_HomeNotification> notifications;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<_HomeNotification> onOpenNotification;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_none, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '通知',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (!hasError && !isLoading)
                Text(
                  '${notifications.length}件',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              IconButton(
                onPressed: hasError || isLoading ? null : onOpenHistory,
                tooltip: '通知履歴',
                icon: const Icon(Icons.history),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasError)
            const _PanelMessage(text: '通知の読み込みに失敗しました')
          else if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (notifications.isEmpty)
            const _PanelMessage(text: '新しい通知はありません')
          else
            for (final notification in notifications) ...[
              _NotificationTile(
                notification: notification,
                onTap: () => onOpenNotification(notification),
              ),
              if (notification != notifications.last) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final _HomeNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _notificationColor(colorScheme, notification.kind);

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(notification.icon, size: 22, color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          notification.timeLabel,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationHistoryScreen extends StatelessWidget {
  const _NotificationHistoryScreen({required this.notifications});

  final List<_HomeNotification> notifications;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知履歴')),
      body: SafeArea(
        child: notifications.isEmpty
            ? const Center(child: Text('通知履歴はありません'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: notifications.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final notification = notifications[index];

                  return _NotificationTile(
                    notification: notification,
                    onTap: () => Navigator.pop(context, notification),
                  );
                },
              ),
      ),
    );
  }
}

class _HomeNotification {
  const _HomeNotification({
    required this.kind,
    required this.icon,
    required this.title,
    required this.message,
    required this.occurredAt,
    this.task,
    this.project,
  });

  final _NotificationKind kind;
  final IconData icon;
  final String title;
  final String message;
  final DateTime? occurredAt;
  final Task? task;
  final Project? project;

  String get timeLabel => _formatNotificationTime(occurredAt);
}

enum _NotificationKind {
  appUpdate,
  newTask,
  projectInvite,
  taskAssignment,
  taskDeadline,
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({
    required this.projects,
    required this.tasks,
    required this.projectById,
    required this.isWide,
    required this.isLoadingProjects,
    required this.isLoadingTasks,
    required this.hasProjectError,
    required this.hasTaskError,
    required this.onOpenProject,
    required this.onOpenTask,
  });

  final List<Project> projects;
  final List<Task> tasks;
  final Map<String, Project> projectById;
  final bool isWide;
  final bool isLoadingProjects;
  final bool isLoadingTasks;
  final bool hasProjectError;
  final bool hasTaskError;
  final ValueChanged<Project> onOpenProject;
  final ValueChanged<Task> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final projectPanel = _QuickAccessPanel(
      icon: Icons.folder_open,
      title: '最近操作したプロジェクト',
      isLoading: isLoadingProjects,
      hasError: hasProjectError,
      emptyText: '最近操作したプロジェクトはありません',
      children: [
        for (final project in projects)
          _ProjectQuickAccessTile(
            project: project,
            onTap: () => onOpenProject(project),
          ),
      ],
    );
    final taskPanel = _QuickAccessPanel(
      icon: Icons.task_alt,
      title: '最近操作したタスク',
      isLoading: isLoadingTasks,
      hasError: hasTaskError,
      emptyText: '最近操作したタスクはありません',
      children: [
        for (final task in tasks)
          _TaskQuickAccessTile(
            task: task,
            project: projectById[task.projectId],
            onTap: () => onOpenTask(task),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'クイックアクセス',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: projectPanel),
              const SizedBox(width: 12),
              Expanded(child: taskPanel),
            ],
          )
        else
          Column(
            children: [projectPanel, const SizedBox(height: 12), taskPanel],
          ),
      ],
    );
  }
}

class _QuickAccessPanel extends StatelessWidget {
  const _QuickAccessPanel({
    required this.icon,
    required this.title,
    required this.isLoading,
    required this.hasError,
    required this.emptyText,
    required this.children,
  });

  final IconData icon;
  final String title;
  final bool isLoading;
  final bool hasError;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasError)
            const _PanelMessage(text: '読み込みに失敗しました')
          else if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (children.isEmpty)
            _PanelMessage(text: emptyText)
          else
            for (final child in children) ...[
              child,
              if (child != children.last) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _ProjectQuickAccessTile extends StatelessWidget {
  const _ProjectQuickAccessTile({required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _QuickAccessTile(
      icon: Icons.folder,
      title: project.name,
      subtitle: '更新 ${_dateTimeFormat.format(project.updatedAt)}',
      onTap: onTap,
    );
  }
}

class _TaskQuickAccessTile extends StatelessWidget {
  const _TaskQuickAccessTile({
    required this.task,
    required this.project,
    required this.onTap,
  });

  final Task task;
  final Project? project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (project != null) project!.name,
      '更新 ${_dateTimeFormat.format(task.updatedAt)}',
      if (task.deadline != null) '期限 ${_dateFormat.format(task.deadline!)}',
    ].join(' / ');

    return _QuickAccessTile(
      icon: task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
      title: task.title.isEmpty ? '無題のタスク' : task.title,
      subtitle: meta,
      onTap: onTap,
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(text),
    );
  }
}

List<Project> _recentProjects(List<Project> projects) {
  final sortedProjects = [...projects];
  sortedProjects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return sortedProjects.take(3).toList();
}

List<Task> _recentTasks(List<Task> tasks) {
  final sortedTasks = [...tasks];
  sortedTasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return sortedTasks.take(3).toList();
}

List<Task> _overdueTasks(List<Task> tasks) {
  final today = DateUtils.dateOnly(DateTime.now());
  final overdueTasks = tasks
      .where((task) => _isTaskOverdue(task, today))
      .toList();

  overdueTasks.sort((a, b) => a.deadline!.compareTo(b.deadline!));
  return overdueTasks;
}

List<Task> _todayFocusTasks(List<Task> tasks) {
  final today = DateUtils.dateOnly(DateTime.now());
  final focusTasks = tasks.where((task) {
    if (task.isDone) {
      return false;
    }

    return _isTaskOverdue(task, today) ||
        _isTaskDueToday(task, today) ||
        _hasReminderToday(task, today);
  }).toList();

  focusTasks.sort((a, b) {
    final bucketCompare = _todayFocusBucket(
      a,
      today,
    ).compareTo(_todayFocusBucket(b, today));
    if (bucketCompare != 0) {
      return bucketCompare;
    }

    return _taskSortDate(a).compareTo(_taskSortDate(b));
  });

  return focusTasks.take(4).toList();
}

List<Task> _highPriorityTasks(List<Task> tasks) {
  final priorityTasks = tasks
      .where((task) => !task.isDone && (task.priority ?? 0) >= 4)
      .toList();

  priorityTasks.sort((a, b) {
    final priorityCompare = (b.priority ?? 0).compareTo(a.priority ?? 0);
    if (priorityCompare != 0) {
      return priorityCompare;
    }

    final dateCompare = _taskSortDate(a).compareTo(_taskSortDate(b));
    if (dateCompare != 0) {
      return dateCompare;
    }

    return b.updatedAt.compareTo(a.updatedAt);
  });

  return priorityTasks.take(4).toList();
}

List<_CommentedTask> _recentlyCommentedTasks(List<Task> tasks) {
  final commentedTasks = <_CommentedTask>[];

  for (final task in tasks) {
    if (task.comments.isEmpty) {
      continue;
    }

    final comments = [...task.comments]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    commentedTasks.add(_CommentedTask(task: task, comment: comments.first));
  }

  commentedTasks.sort(
    (a, b) => b.comment.createdAt.compareTo(a.comment.createdAt),
  );
  return commentedTasks.take(3).toList();
}

List<_ProjectProgress> _projectProgress(
  List<Project> projects,
  List<Task> tasks,
) {
  final sortedProjects = [...projects]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  return sortedProjects.take(4).map((project) {
    final projectTasks = tasks
        .where((task) => task.projectId == project.id)
        .toList();
    final doneCount = projectTasks.where((task) => task.isDone).length;

    return _ProjectProgress(
      project: project,
      doneCount: doneCount,
      totalCount: projectTasks.length,
    );
  }).toList();
}

List<_HomeNotification> _homeNotifications({
  required List<Project> projects,
  required List<Task> tasks,
}) {
  return _buildHomeNotifications(
    projects: projects,
    tasks: tasks,
    compact: true,
  ).take(6).toList();
}

List<_HomeNotification> _notificationHistory({
  required List<Project> projects,
  required List<Task> tasks,
}) {
  final notifications = _buildHomeNotifications(
    projects: projects,
    tasks: tasks,
    compact: false,
  );
  notifications.sort(_compareNotificationsByTime);
  return notifications.take(80).toList();
}

List<_HomeNotification> _buildHomeNotifications({
  required List<Project> projects,
  required List<Task> tasks,
  required bool compact,
}) {
  final now = DateTime.now();
  final today = DateUtils.dateOnly(now);
  final notifications = <_HomeNotification>[
    const _HomeNotification(
      kind: _NotificationKind.appUpdate,
      icon: Icons.system_update_alt,
      title: 'アプリケーション更新',
      message: '現在、新しい更新通知はありません',
      occurredAt: null,
    ),
  ];

  final dueTasks = tasks.where((task) {
    final deadline = task.deadline;
    if (task.isDone || deadline == null) {
      return false;
    }

    final daysUntilDue = DateUtils.dateOnly(deadline).difference(today).inDays;
    return daysUntilDue <= 3;
  }).toList()..sort((a, b) => a.deadline!.compareTo(b.deadline!));

  for (final task in dueTasks.take(compact ? 2 : dueTasks.length)) {
    notifications.add(
      _HomeNotification(
        kind: _NotificationKind.taskDeadline,
        icon: Icons.event_busy,
        title: 'タスク期限',
        message:
            '${_taskTitle(task)} の期限は ${_formatDeadlineNotice(task.deadline!, today)} です',
        occurredAt: task.deadline,
        task: task,
      ),
    );
  }

  final assignedTasks =
      tasks
          .where(
            (task) =>
                !task.isDone && (task.assigneeName?.trim().isNotEmpty ?? false),
          )
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  for (final task in assignedTasks.take(compact ? 2 : assignedTasks.length)) {
    notifications.add(
      _HomeNotification(
        kind: _NotificationKind.taskAssignment,
        icon: Icons.assignment_ind,
        title: 'タスクの割り当て',
        message: '${task.assigneeName} に ${_taskTitle(task)} が割り当てられています',
        occurredAt: task.updatedAt,
        task: task,
      ),
    );
  }

  final recentTasks = tasks.where((task) {
    return now.difference(task.createdAt).inDays <= 7;
  }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  for (final task in recentTasks.take(compact ? 2 : recentTasks.length)) {
    notifications.add(
      _HomeNotification(
        kind: _NotificationKind.newTask,
        icon: Icons.add_task,
        title: '新しいタスク',
        message: '${_taskTitle(task)} が追加されました',
        occurredAt: task.createdAt,
        task: task,
      ),
    );
  }

  final sharedProjects =
      projects.where((project) => project.memberIds.length > 1).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  for (final project in sharedProjects.take(
    compact ? 1 : sharedProjects.length,
  )) {
    notifications.add(
      _HomeNotification(
        kind: _NotificationKind.projectInvite,
        icon: Icons.group_add,
        title: 'プロジェクト招待',
        message: '${project.name} への参加通知があります',
        occurredAt: project.updatedAt,
        project: project,
      ),
    );
  }

  return notifications;
}

int _compareNotificationsByTime(_HomeNotification a, _HomeNotification b) {
  final aTime = a.occurredAt;
  final bTime = b.occurredAt;

  if (aTime == null && bTime == null) {
    return a.title.compareTo(b.title);
  }
  if (aTime == null) {
    return 1;
  }
  if (bTime == null) {
    return -1;
  }

  return bTime.compareTo(aTime);
}

bool _isTaskOverdue(Task task, DateTime today) {
  final deadline = task.deadline;

  if (task.isDone || deadline == null) {
    return false;
  }

  return DateUtils.dateOnly(deadline).isBefore(today);
}

bool _isTaskDueToday(Task task, DateTime today) {
  final deadline = task.deadline;

  if (task.isDone || deadline == null) {
    return false;
  }

  return DateUtils.isSameDay(deadline, today);
}

bool _hasReminderToday(Task task, DateTime today) {
  final reminder = task.reminder;

  if (task.isDone || reminder == null) {
    return false;
  }

  return DateUtils.isSameDay(reminder, today);
}

int _todayFocusBucket(Task task, DateTime today) {
  if (_isTaskOverdue(task, today)) {
    return 0;
  }
  if (_isTaskDueToday(task, today)) {
    return 1;
  }
  if (_hasReminderToday(task, today)) {
    return 2;
  }

  return 3;
}

DateTime _taskSortDate(Task task) {
  return task.deadline ??
      task.reminder ??
      task.startDate ??
      DateTime(9999, 12, 31);
}

Color _notificationColor(ColorScheme colorScheme, _NotificationKind kind) {
  switch (kind) {
    case _NotificationKind.appUpdate:
      return colorScheme.primary;
    case _NotificationKind.newTask:
      return colorScheme.tertiary;
    case _NotificationKind.projectInvite:
      return colorScheme.secondary;
    case _NotificationKind.taskAssignment:
      return colorScheme.primary;
    case _NotificationKind.taskDeadline:
      return colorScheme.error;
  }
}

String _taskTitle(Task task) {
  return task.title.isEmpty ? '無題のタスク' : task.title;
}

String _taskTimingSubtitle(Task task, Map<String, Project> projectById) {
  final today = DateUtils.dateOnly(DateTime.now());
  final parts = <String>[
    if (_projectName(task, projectById) != null)
      _projectName(task, projectById)!,
  ];

  if (_isTaskOverdue(task, today) && task.deadline != null) {
    parts.add('期限 ${_formatDeadlineNotice(task.deadline!, today)}');
  } else if (_isTaskDueToday(task, today)) {
    parts.add('期限 今日');
  } else if (_hasReminderToday(task, today)) {
    parts.add('リマインダー 今日');
  } else if (task.deadline != null) {
    parts.add('期限 ${_dateFormat.format(task.deadline!)}');
  }

  if (task.assigneeName?.trim().isNotEmpty ?? false) {
    parts.add(task.assigneeName!.trim());
  }

  return parts.isEmpty ? '詳細未設定' : parts.join(' / ');
}

String _taskPrioritySubtitle(Task task, Map<String, Project> projectById) {
  final parts = <String>[
    '重要度 ${task.priority ?? '-'}',
    if (_projectName(task, projectById) != null)
      _projectName(task, projectById)!,
    if (task.deadline != null) '期限 ${_dateFormat.format(task.deadline!)}',
  ];

  return parts.join(' / ');
}

String? _projectName(Task task, Map<String, Project> projectById) {
  final projectId = task.projectId;

  if (projectId == null) {
    return null;
  }

  final projectName = projectById[projectId]?.name.trim();
  return projectName?.isEmpty ?? true ? null : projectName;
}

String _commentSnippet(TaskComment comment) {
  final snippet = comment.body.trim().replaceAll(RegExp(r'\s+'), ' ');

  if (snippet.isEmpty) {
    return 'コメント内容なし';
  }

  return snippet;
}

String _formatDeadlineNotice(DateTime deadline, DateTime today) {
  final daysUntilDue = DateUtils.dateOnly(deadline).difference(today).inDays;

  if (daysUntilDue < 0) {
    return '${daysUntilDue.abs()}日前';
  }
  if (daysUntilDue == 0) {
    return '今日';
  }
  if (daysUntilDue == 1) {
    return '明日';
  }

  return '$daysUntilDue日後';
}

String _formatNotificationTime(DateTime? date) {
  if (date == null) {
    return 'システム';
  }

  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(date);
  final dayDiff = today.difference(day).inDays;

  if (dayDiff == 0) {
    return '今日';
  }
  if (dayDiff == 1) {
    return '昨日';
  }
  if (dayDiff > 1 && dayDiff < 7) {
    return '$dayDiff日前';
  }

  return _dateFormat.format(date);
}
