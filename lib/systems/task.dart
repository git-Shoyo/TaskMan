import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  String title;
  String id;
  DateTime? deadline;
  DateTime? startDate;
  bool isDone;
  String? memo;
  DateTime createdAt;
  DateTime updatedAt;
  int? priority;
  String category;
  String? projectId;
  String? assigneeId;
  String? assigneeName;
  Duration? estimatedTime;
  DateTime? reminder;
  List<String> tags;
  List<TaskTodo> todos;
  List<TaskComment> comments;
  String? externalSource;
  String? externalId;
  String? externalUrl;
  String? externalPlanId;
  String? externalBucketId;
  DateTime? externalUpdatedAt;

  Task({
    required this.title,
    required this.id,
    this.deadline,
    this.startDate,
    this.isDone = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.priority,
    this.category = "",
    this.projectId,
    this.assigneeId,
    this.assigneeName,
    this.memo,
    this.estimatedTime,
    this.reminder,
    List<String>? tags,
    List<TaskTodo>? todos,
    List<TaskComment>? comments,
    this.externalSource,
    this.externalId,
    this.externalUrl,
    this.externalPlanId,
    this.externalBucketId,
    this.externalUpdatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       tags = tags ?? [],
       todos = todos ?? [],
       comments = comments ?? [];

  double get completionRatio {
    if (todos.isEmpty) {
      return isDone ? 1 : 0;
    }

    final doneCount = todos.where((todo) => todo.isDone).length;
    return doneCount / todos.length;
  }

  int get completionPercent => (completionRatio * 100).round();

  factory Task.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return Task(
      id: doc.id,
      title: data['title'] as String? ?? '',
      deadline: readDateTime(data['deadline']),
      startDate: readDateTime(data['startDate']),
      isDone: data['isDone'] as bool? ?? false,
      memo: data['memo'] as String?,
      createdAt: readDateTime(data['createdAt']),
      updatedAt: readDateTime(data['updatedAt']),
      priority: data['priority'] as int?,
      category: data['category'] as String? ?? '',
      projectId: data['projectId'] as String?,
      assigneeId: data['assigneeId'] as String?,
      assigneeName: data['assigneeName'] as String?,
      estimatedTime: _readDuration(data['estimatedTimeSeconds']),
      reminder: readDateTime(data['reminder']),
      tags: List<String>.from(data['tags'] as List? ?? const []),
      todos: _readTodos(data['todos']),
      comments: _readComments(data['comments']),
      externalSource: data['externalSource'] as String?,
      externalId: data['externalId'] as String?,
      externalUrl: data['externalUrl'] as String?,
      externalPlanId: data['externalPlanId'] as String?,
      externalBucketId: data['externalBucketId'] as String?,
      externalUpdatedAt: readDateTime(data['externalUpdatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'deadline': deadline == null ? null : Timestamp.fromDate(deadline!),
      'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
      'isDone': isDone,
      'memo': memo,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'priority': priority,
      'category': category,
      'projectId': projectId,
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
      'estimatedTimeSeconds': estimatedTime?.inSeconds,
      'reminder': reminder == null ? null : Timestamp.fromDate(reminder!),
      'tags': tags,
      'todos': todos.map((todo) => todo.toFirestore()).toList(),
      'comments': comments.map((comment) => comment.toFirestore()).toList(),
      'externalSource': externalSource,
      'externalId': externalId,
      'externalUrl': externalUrl,
      'externalPlanId': externalPlanId,
      'externalBucketId': externalBucketId,
      'externalUpdatedAt': externalUpdatedAt == null
          ? null
          : Timestamp.fromDate(externalUpdatedAt!),
    };
  }

  static Duration? _readDuration(Object? value) {
    if (value is int) {
      return Duration(seconds: value);
    }
    return null;
  }

  static List<TaskTodo> _readTodos(Object? value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map((todo) => TaskTodo.fromMap(Map<String, dynamic>.from(todo)))
        .toList();
  }

  static List<TaskComment> _readComments(Object? value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (comment) => TaskComment.fromMap(Map<String, dynamic>.from(comment)),
        )
        .toList();
  }
}

class TaskTodo {
  String id;
  String title;
  bool isDone;
  DateTime createdAt;
  DateTime? completedAt;
  String? assigneeId;
  String? assigneeName;

  TaskTodo({
    required this.id,
    required this.title,
    this.isDone = false,
    DateTime? createdAt,
    this.completedAt,
    this.assigneeId,
    this.assigneeName,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TaskTodo.fromMap(Map<String, dynamic> data) {
    return TaskTodo(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? '',
      isDone: data['isDone'] as bool? ?? false,
      createdAt: readDateTime(data['createdAt']) ?? DateTime.now(),
      completedAt: readDateTime(data['completedAt']),
      assigneeId: data['assigneeId'] as String?,
      assigneeName: data['assigneeName'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'title': title,
      'isDone': isDone,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt == null
          ? null
          : Timestamp.fromDate(completedAt!),
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
    };
  }
}

class TaskComment {
  String id;
  String body;
  String? authorId;
  String authorName;
  DateTime createdAt;

  TaskComment({
    required this.id,
    required this.body,
    this.authorId,
    required this.authorName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TaskComment.fromMap(Map<String, dynamic> data) {
    return TaskComment(
      id: data['id'] as String? ?? '',
      body: data['body'] as String? ?? '',
      authorId: data['authorId'] as String?,
      authorName: data['authorName'] as String? ?? '匿名',
      createdAt: readDateTime(data['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'body': body,
      'authorId': authorId,
      'authorName': authorName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

DateTime? readDateTime(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}
