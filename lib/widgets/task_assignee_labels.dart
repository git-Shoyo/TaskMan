import 'package:flutter/widgets.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/task.dart';

class TaskAssigneeLabelsBuilder extends StatelessWidget {
  const TaskAssigneeLabelsBuilder({
    super.key,
    required this.tasks,
    required this.userRepository,
    required this.builder,
  });

  final List<Task> tasks;
  final UserRepository userRepository;
  final Widget Function(BuildContext context, Map<String, String> labels)
  builder;

  @override
  Widget build(BuildContext context) {
    final fallbackLabels = taskAssigneeSnapshotLabels(tasks);
    final assigneeIds = taskAssigneeIds(tasks);

    if (assigneeIds.isEmpty) {
      return builder(context, fallbackLabels);
    }

    return StreamBuilder<List<AppUser>>(
      stream: userRepository.watchUsersByIds(assigneeIds),
      builder: (context, snapshot) {
        return builder(
          context,
          taskAssigneeLabelsFromUsers(
            snapshot.data ?? const <AppUser>[],
            fallbackLabels: fallbackLabels,
          ),
        );
      },
    );
  }
}

List<String> taskAssigneeIds(Iterable<Task> tasks) {
  return (tasks
      .map((task) => task.assigneeId?.trim())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort());
}

Map<String, String> taskAssigneeSnapshotLabels(Iterable<Task> tasks) {
  final labels = <String, String>{};

  for (final task in tasks) {
    final id = task.assigneeId?.trim();
    final label = task.assigneeName?.trim();
    if (id == null ||
        id.isEmpty ||
        label == null ||
        label.isEmpty ||
        labels.containsKey(id)) {
      continue;
    }

    labels[id] = label;
  }

  return labels;
}

Map<String, String> taskAssigneeLabelsFromUsers(
  Iterable<AppUser> users, {
  Map<String, String> fallbackLabels = const {},
}) {
  final labels = Map<String, String>.from(fallbackLabels);

  for (final user in users) {
    final id = user.id.trim();
    final label = user.label.trim();
    if (id.isEmpty || label.isEmpty) {
      continue;
    }

    labels[id] = label;
  }

  return labels;
}

String taskAssigneeLabel(Task task, Map<String, String> labels) {
  final assigneeId = task.assigneeId?.trim();
  if (assigneeId != null && assigneeId.isNotEmpty) {
    final label = labels[assigneeId]?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
  }

  return task.assigneeName?.trim() ?? '';
}
