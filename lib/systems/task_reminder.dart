import 'package:taskman/systems/task.dart';

const defaultReminderCatchUpWindow = Duration(days: 1);

String taskReminderKey(Task task) {
  final reminder = task.reminder;
  if (reminder == null) {
    return '${task.id}:none';
  }

  return '${task.id}:${reminder.millisecondsSinceEpoch}';
}

bool isTaskReminderDue(
  Task task, {
  required DateTime now,
  Duration catchUpWindow = defaultReminderCatchUpWindow,
}) {
  final reminder = task.reminder;

  if (task.isDone || reminder == null || reminder.isAfter(now)) {
    return false;
  }

  return now.difference(reminder) <= catchUpWindow;
}

List<Task> dueTaskReminders(
  Iterable<Task> tasks, {
  required DateTime now,
  Set<String> ignoredKeys = const {},
  Duration catchUpWindow = defaultReminderCatchUpWindow,
}) {
  final dueTasks = tasks
      .where(
        (task) =>
            isTaskReminderDue(task, now: now, catchUpWindow: catchUpWindow) &&
            !ignoredKeys.contains(taskReminderKey(task)),
      )
      .toList();

  dueTasks.sort((a, b) => a.reminder!.compareTo(b.reminder!));
  return dueTasks;
}

DateTime? nextTaskReminderTime(
  Iterable<Task> tasks, {
  required DateTime now,
  Set<String> ignoredKeys = const {},
}) {
  DateTime? nextReminder;

  for (final task in tasks) {
    final reminder = task.reminder;

    if (task.isDone ||
        reminder == null ||
        !reminder.isAfter(now) ||
        ignoredKeys.contains(taskReminderKey(task))) {
      continue;
    }

    if (nextReminder == null || reminder.isBefore(nextReminder)) {
      nextReminder = reminder;
    }
  }

  return nextReminder;
}
