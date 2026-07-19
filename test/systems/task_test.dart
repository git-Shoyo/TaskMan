import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskman/systems/task.dart';

void main() {
  group('Task', () {
    test('calculates completion from todos before task flag', () {
      final task = Task(
        id: 'task-1',
        title: 'Release',
        isDone: true,
        todos: [
          TaskTodo(id: 'todo-1', title: 'Build', isDone: true),
          TaskTodo(id: 'todo-2', title: 'Ship'),
        ],
      );

      expect(task.completionRatio, 0.5);
      expect(task.completionPercent, 50);
    });

    test('serializes planning metadata', () {
      final start = DateTime(2026, 7, 19);
      final reminder = DateTime(2026, 7, 20, 9);
      final task = Task(
        id: 'task-1',
        title: 'Plan sprint',
        startDate: start,
        estimatedTime: const Duration(hours: 2, minutes: 30),
        reminder: reminder,
        tags: const ['planning', 'team'],
      );

      final data = task.toFirestore();

      expect(data['estimatedTimeSeconds'], 9000);
      expect((data['reminder'] as Timestamp).toDate(), reminder);
      expect(data['tags'], ['planning', 'team']);
    });
  });
}
