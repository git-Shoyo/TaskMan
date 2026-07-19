import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory Project.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return Project(
      id: doc.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String?,
      ownerId: data['ownerId'] as String? ?? '',
      memberIds: List<String>.from(data['memberIds'] as List? ?? const []),
      memberRoles: Map<String, String>.from(
        data['memberRoles'] as Map? ?? const {},
      ),
      createdAt: _readDateTime(data['createdAt']) ?? DateTime.now(),
      updatedAt: _readDateTime(data['updatedAt']) ?? DateTime.now(),
      startDate: _readDateTime(data['startDate']),
      deadline: _readDateTime(data['deadline']),
      isArchived: data['isArchived'] as bool? ?? false,
      color: data['color'] as String? ?? '#2196F3',
      icon: data['icon'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'nameKey': normalizeNameKey(name),
      'description': description,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'memberRoles': memberRoles,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
      'deadline': deadline == null ? null : Timestamp.fromDate(deadline!),
      'isArchived': isArchived,
      'color': color,
      'icon': icon,
    };
  }

  static String normalizeNameKey(String name) {
    return name.trim().toLowerCase();
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
}
