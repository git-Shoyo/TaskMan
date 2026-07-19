import 'package:flutter_test/flutter_test.dart';
import 'package:taskman/systems/task.dart';
import 'package:taskman/systems/task_reminder.dart';

void main() {
  group('task reminders', () {
    test('finds due reminders that have not been shown', () {
      final now = DateTime(2026, 7, 19, 10);
      final dueTask = Task(
        id: 'due',
        title: 'Due',
        reminder: now.subtract(const Duration(minutes: 5)),
      );
      final futureTask = Task(
        id: 'future',
        title: 'Future',
        reminder: now.add(const Duration(minutes: 5)),
      );
      final doneTask = Task(
        id: 'done',
        title: 'Done',
        isDone: true,
        reminder: now.subtract(const Duration(minutes: 5)),
      );

      final reminders = dueTaskReminders([
        futureTask,
        dueTask,
        doneTask,
      ], now: now);

      expect(reminders, [dueTask]);
    });

    test('ignores stale reminder keys and old reminders', () {
      final now = DateTime(2026, 7, 19, 10);
      final shownTask = Task(
        id: 'shown',
        title: 'Shown',
        reminder: now.subtract(const Duration(minutes: 5)),
      );
      final oldTask = Task(
        id: 'old',
        title: 'Old',
        reminder: now.subtract(const Duration(days: 2)),
      );

      final reminders = dueTaskReminders(
        [shownTask, oldTask],
        now: now,
        ignoredKeys: {taskReminderKey(shownTask)},
      );

      expect(reminders, isEmpty);
    });

    test('returns the next future reminder time', () {
      final now = DateTime(2026, 7, 19, 10);
      final firstTask = Task(
        id: 'first',
        title: 'First',
        reminder: now.add(const Duration(minutes: 20)),
      );
      final secondTask = Task(
        id: 'second',
        title: 'Second',
        reminder: now.add(const Duration(hours: 1)),
      );

      expect(
        nextTaskReminderTime([secondTask, firstTask], now: now),
        firstTask.reminder,
      );
    });
  });
}
