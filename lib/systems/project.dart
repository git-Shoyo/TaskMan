class Project {
  String id;
  String name;
  String? description;

  String ownerId;
  List<String> memberIds;
  Map<String, String> memberRoles;

  DateTime createdAt;
  DateTime updatedAt;
  DateTime? startDate;
  DateTime? deadline;

  bool isArchived;

  String color;
  String? icon;

  Project({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    this.memberIds = const [],
    this.memberRoles = const {},
    required this.createdAt,
    required this.updatedAt,
    this.startDate,
    this.deadline,
    this.isArchived = false,
    this.color = '#2196F3',
    this.icon,
  });
}
