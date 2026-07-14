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
  Duration? estimatedTime;
  DateTime? reminder;
  List<String> tags;

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
    this.memo,
    this.estimatedTime,
    this.reminder,
    List<String>? tags,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       tags = tags ?? [];

  factory Task.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return Task(
      id: doc.id,
      title: data['title'] as String? ?? '',
      deadline: _readDateTime(data['deadline']),
      startDate: _readDateTime(data['startDate']),
      isDone: data['isDone'] as bool? ?? false,
      memo: data['memo'] as String?,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
      priority: data['priority'] as int?,
      category: data['category'] as String? ?? '',
      projectId: data['projectId'] as String?,
      estimatedTime: _readDuration(data['estimatedTimeSeconds']),
      reminder: _readDateTime(data['reminder']),
      tags: List<String>.from(data['tags'] as List? ?? const []),
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
      'estimatedTimeSeconds': estimatedTime?.inSeconds,
      'reminder': reminder == null ? null : Timestamp.fromDate(reminder!),
      'tags': tags,
    };
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static Duration? _readDuration(Object? value) {
    if (value is int) {
      return Duration(seconds: value);
    }
    return null;
  }
}
