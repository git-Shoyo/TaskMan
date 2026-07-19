import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/screens/task_detail_screen.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';

final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final projectRepository = ProjectRepository();
  final taskRepository = TaskRepository();

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
            if (taskSnapshot.hasError) {
              return const Center(child: Text('タスクの読み込みに失敗しました'));
            }

            if (taskSnapshot.connectionState == ConnectionState.waiting &&
                !taskSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final projectById = {
              for (final project in projects) project.id: project,
            };
            final tasks = _sortTasks(taskSnapshot.data ?? const <Task>[]);

            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Row(
                    children: [
                      const Icon(Icons.task_alt),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'タスク',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      Text('${tasks.length}件'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (tasks.isEmpty)
                    const _EmptyTaskList()
                  else
                    for (final task in tasks) ...[
                      _TaskListTile(
                        task: task,
                        project: projectById[task.projectId],
                        onTap: () => _openTask(task, projectById),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({
    required this.task,
    required this.project,
    required this.onTap,
  });

  final Task task;
  final Project? project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                color: task.isDone ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title.isEmpty ? '無題のタスク' : task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (project != null)
                          _TaskMeta(icon: Icons.folder, text: project!.name),
                        _TaskMeta(
                          icon: Icons.event,
                          text: _formatDate(task.deadline),
                        ),
                        if (task.startDate != null)
                          _TaskMeta(
                            icon: Icons.play_arrow,
                            text: _formatDate(task.startDate),
                          ),
                        _TaskMeta(
                          icon: Icons.priority_high,
                          text: _formatPriority(task.priority),
                        ),
                        if (task.category.trim().isNotEmpty)
                          _TaskMeta(icon: Icons.label, text: task.category),
                        if (task.assigneeName?.trim().isNotEmpty ?? false)
                          _TaskMeta(
                            icon: Icons.person_outline,
                            text: task.assigneeName!,
                          ),
                        _TaskMeta(
                          icon: Icons.percent,
                          text: '${task.completionPercent}%',
                        ),
                      ],
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

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(text)],
    );
  }
}

class _EmptyTaskList extends StatelessWidget {
  const _EmptyTaskList();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Text('タスクがありません'),
    );
  }
}

List<Task> _sortTasks(List<Task> tasks) {
  final sortedTasks = [...tasks];
  sortedTasks.sort((a, b) {
    if (a.isDone != b.isDone) {
      return a.isDone ? 1 : -1;
    }

    return b.updatedAt.compareTo(a.updatedAt);
  });

  return sortedTasks;
}

String _formatDate(DateTime? date) {
  if (date == null) {
    return '未設定';
  }

  return _dateFormat.format(date);
}

String _formatPriority(int? priority) {
  if (priority == null) {
    return '重要度なし';
  }

  return '重要度 $priority';
}
