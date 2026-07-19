import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskman/systems/task.dart';

class TaskRepository {
  TaskRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _firestore.collection('tasks');

  DocumentReference<Map<String, dynamic>> _taskDoc(String taskId) {
    return _tasks.doc(taskId);
  }

  Stream<List<Task>> watchTasks({
    String? projectId,
    Iterable<String>? projectIds,
  }) {
    Query<Map<String, dynamic>> query = _tasks;

    if (projectId != null) {
      query = query.where('projectId', isEqualTo: projectId);
    }

    final normalizedProjectIds = projectIds
        ?.map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (projectId == null && normalizedProjectIds != null) {
      if (normalizedProjectIds.isEmpty) {
        return Stream.value(const <Task>[]);
      }

      if (normalizedProjectIds.length == 1) {
        query = query.where('projectId', isEqualTo: normalizedProjectIds.first);
      } else if (normalizedProjectIds.length <= 30) {
        query = query.where('projectId', whereIn: normalizedProjectIds);
      } else {
        return _watchTasksForProjectChunks(normalizedProjectIds);
      }
    }

    return query.snapshots().map((snapshot) {
      final tasks = snapshot.docs.map(Task.fromFirestore).toList();
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tasks;
    });
  }

  Stream<List<Task>> _watchTasksForProjectChunks(List<String> projectIds) {
    final chunks = <List<String>>[];
    for (var start = 0; start < projectIds.length; start += 30) {
      final end = start + 30 > projectIds.length
          ? projectIds.length
          : start + 30;
      chunks.add(projectIds.sublist(start, end));
    }

    late StreamController<List<Task>> controller;
    final latestTasks = List<List<Task>?>.filled(chunks.length, null);
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitMergedTasks() {
      if (latestTasks.any((tasks) => tasks == null)) {
        return;
      }

      final mergedTasks = latestTasks.expand((tasks) => tasks!).toList();
      mergedTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(mergedTasks);
    }

    controller = StreamController<List<Task>>(
      onListen: () {
        for (var index = 0; index < chunks.length; index += 1) {
          final subscription = _tasks
              .where('projectId', whereIn: chunks[index])
              .snapshots()
              .listen((snapshot) {
                latestTasks[index] = snapshot.docs
                    .map(Task.fromFirestore)
                    .toList();
                emitMergedTasks();
              }, onError: controller.addError);
          subscriptions.add(subscription);
        }
      },
      onCancel: () async {
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      },
    );

    return controller.stream;
  }

  Stream<Task?> watchTask(String taskId) {
    return _taskDoc(taskId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }

      return Task.fromFirestore(snapshot);
    });
  }

  Future<void> addTask(Task task) async {
    final doc = task.id.isEmpty ? _tasks.doc() : _tasks.doc(task.id);
    task.id = doc.id;
    task.createdAt = DateTime.now();
    task.updatedAt = task.createdAt;

    await doc.set(task.toFirestore());
  }

  Future<void> updateTask(Task task) async {
    task.updatedAt = DateTime.now();
    await _tasks.doc(task.id).update(task.toFirestore());
  }

  Future<void> updateTaskDetails({
    required String taskId,
    DateTime? startDate,
    DateTime? deadline,
    int? priority,
    required String category,
  }) async {
    await _taskDoc(taskId).update({
      'startDate': startDate == null ? null : Timestamp.fromDate(startDate),
      'deadline': deadline == null ? null : Timestamp.fromDate(deadline),
      'priority': priority,
      'category': category.trim(),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> setTaskDone({required Task task, required bool isDone}) async {
    final now = DateTime.now();

    await _mutateTask(task.id, (currentTask) {
      currentTask.isDone = isDone;

      for (final todo in currentTask.todos) {
        todo.isDone = isDone;
        todo.completedAt = isDone ? (todo.completedAt ?? now) : null;
      }
    }, now: now);
  }

  Future<void> addTodo({
    required String taskId,
    required String title,
    String? assigneeId,
    String? assigneeName,
  }) async {
    final trimmedTitle = title.trim();

    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Todo title must not be empty.',
      );
    }

    final now = DateTime.now();
    final todo = TaskTodo(
      id: _tasks.doc().id,
      title: trimmedTitle,
      assigneeId: assigneeId?.trim().isEmpty ?? true
          ? null
          : assigneeId!.trim(),
      assigneeName: assigneeName?.trim().isEmpty ?? true
          ? null
          : assigneeName!.trim(),
      createdAt: now,
    );

    await _mutateTask(taskId, (task) {
      task.todos.add(todo);
      task.isDone = false;
    }, now: now);
  }

  Future<void> setTodoDone({
    required String taskId,
    required String todoId,
    required bool isDone,
  }) async {
    final now = DateTime.now();

    await _mutateTask(taskId, (task) {
      for (final todo in task.todos) {
        if (todo.id == todoId) {
          todo.isDone = isDone;
          todo.completedAt = isDone ? now : null;
          break;
        }
      }

      task.isDone =
          task.todos.isNotEmpty && task.todos.every((todo) => todo.isDone);
    }, now: now);
  }

  Future<void> deleteTodo({
    required String taskId,
    required String todoId,
  }) async {
    final now = DateTime.now();

    await _mutateTask(taskId, (task) {
      task.todos.removeWhere((todo) => todo.id == todoId);
      if (task.todos.isNotEmpty) {
        task.isDone = task.todos.every((todo) => todo.isDone);
      }
    }, now: now);
  }

  Future<void> addComment({
    required String taskId,
    required String body,
    String? authorId,
    required String authorName,
  }) async {
    final trimmedBody = body.trim();
    final trimmedAuthorName = authorName.trim();

    if (trimmedBody.isEmpty) {
      throw ArgumentError.value(
        body,
        'body',
        'Comment body must not be empty.',
      );
    }

    final now = DateTime.now();
    final comment = TaskComment(
      id: _tasks.doc().id,
      body: trimmedBody,
      authorId: authorId?.trim().isEmpty ?? true ? null : authorId!.trim(),
      authorName: trimmedAuthorName.isEmpty ? '匿名' : trimmedAuthorName,
      createdAt: now,
    );

    await _mutateTask(taskId, (task) {
      task.comments.insert(0, comment);
    }, now: now);
  }

  Future<void> deleteComment({
    required String taskId,
    required String commentId,
  }) async {
    final now = DateTime.now();

    await _mutateTask(taskId, (task) {
      task.comments.removeWhere((comment) => comment.id == commentId);
    }, now: now);
  }

  Future<void> deleteTask(String taskId) async {
    await _tasks.doc(taskId).delete();
  }

  Future<void> deleteTasksByProjectId(String projectId) async {
    final snapshot = await _tasks
        .where('projectId', isEqualTo: projectId)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    WriteBatch batch = _firestore.batch();
    var operationCount = 0;

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
      operationCount++;

      if (operationCount == 450) {
        await batch.commit();
        batch = _firestore.batch();
        operationCount = 0;
      }
    }

    if (operationCount > 0) {
      await batch.commit();
    }
  }

  Future<void> _mutateTask(
    String taskId,
    void Function(Task task) mutate, {
    required DateTime now,
  }) async {
    final taskDoc = _taskDoc(taskId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(taskDoc);

      if (!snapshot.exists) {
        throw StateError('Task $taskId does not exist.');
      }

      final task = Task.fromFirestore(snapshot);
      mutate(task);
      task.updatedAt = now;

      transaction.update(taskDoc, task.toFirestore());
    });
  }
}
