import 'package:cloud_firestore/cloud_firestore.dart';

enum ProjectIssueStatus {
  open,
  closed;

  static ProjectIssueStatus fromValue(Object? value) {
    final rawValue = value?.toString().trim().toLowerCase();
    return ProjectIssueStatus.values.firstWhere(
      (status) => status.name == rawValue,
      orElse: () => ProjectIssueStatus.open,
    );
  }
}

class ProjectIssue {
  String id;
  String projectId;
  String? organizationId;
  int? issueNumber;

  String title;
  String? body;
  ProjectIssueStatus status;
  List<String> labels;

  String? assigneeId;
  String? assigneeName;
  String? authorId;
  String authorName;

  String? externalSource;
  String? externalId;
  String? externalUrl;

  DateTime createdAt;
  DateTime updatedAt;
  DateTime? closedAt;

  ProjectIssue({
    required this.id,
    required this.projectId,
    this.organizationId,
    this.issueNumber,
    required this.title,
    this.body,
    this.status = ProjectIssueStatus.open,
    List<String>? labels,
    this.assigneeId,
    this.assigneeName,
    this.authorId,
    this.authorName = '匿名',
    this.externalSource,
    this.externalId,
    this.externalUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.closedAt,
  }) : labels = labels ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isOpen => status == ProjectIssueStatus.open;

  factory ProjectIssue.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return ProjectIssue(
      id: doc.id,
      projectId: data['projectId'] as String? ?? '',
      organizationId: data['organizationId'] as String?,
      issueNumber: data['issueNumber'] as int?,
      title: data['title'] as String? ?? '',
      body: data['body'] as String?,
      status: ProjectIssueStatus.fromValue(data['status']),
      labels: List<String>.from(data['labels'] as List? ?? const []),
      assigneeId: data['assigneeId'] as String?,
      assigneeName: data['assigneeName'] as String?,
      authorId: data['authorId'] as String?,
      authorName: data['authorName'] as String? ?? '匿名',
      externalSource: data['externalSource'] as String?,
      externalId: data['externalId'] as String?,
      externalUrl: data['externalUrl'] as String?,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
      closedAt: _readDateTime(data['closedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'projectId': projectId,
      'organizationId': organizationId,
      'issueNumber': issueNumber,
      'title': title,
      'body': body,
      'status': status.name,
      'isOpen': isOpen,
      'labels': labels,
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
      'authorId': authorId,
      'authorName': authorName,
      'externalSource': externalSource,
      'externalId': externalId,
      'externalUrl': externalUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'closedAt': closedAt == null ? null : Timestamp.fromDate(closedAt!),
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
}
