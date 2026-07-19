import 'package:cloud_firestore/cloud_firestore.dart';

class Organization {
  String id;
  String name;
  String? description;

  String ownerId;
  List<String> memberIds;
  Map<String, String> memberRoles;

  DateTime createdAt;
  DateTime updatedAt;

  bool isArchived;
  String color;

  Organization({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    this.memberIds = const [],
    this.memberRoles = const {},
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.color = '#2196F3',
  });

  factory Organization.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return Organization(
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
      isArchived: data['isArchived'] as bool? ?? false,
      color: data['color'] as String? ?? '#2196F3',
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
      'isArchived': isArchived,
      'color': color,
    };
  }

  bool hasMember(String userId) {
    final trimmedUserId = userId.trim();
    return trimmedUserId.isNotEmpty && memberIds.contains(trimmedUserId);
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
