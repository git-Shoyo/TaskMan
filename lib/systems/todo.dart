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
    this.estimatedTime,
    this.reminder,
    List<String>? tags,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       tags = tags ?? [];
}
