import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskman/systems/issue.dart';

class IssueRepository {
  IssueRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _issues =>
      _firestore.collection('issues');

  CollectionReference<Map<String, dynamic>> get _issueCounters =>
      _firestore.collection('issueCounters');

  DocumentReference<Map<String, dynamic>> _issueDoc(String issueId) {
    return _issues.doc(issueId);
  }

  Stream<List<ProjectIssue>> watchIssues({
    String? projectId,
    Iterable<String>? projectIds,
    String? organizationId,
    ProjectIssueStatus? status,
  }) {
    Query<Map<String, dynamic>> query = _issues;

    if (projectId != null && projectId.trim().isNotEmpty) {
      query = query.where('projectId', isEqualTo: projectId.trim());
    } else {
      final normalizedProjectIds = projectIds
          ?.map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (normalizedProjectIds != null) {
        if (normalizedProjectIds.isEmpty) {
          return Stream.value(const <ProjectIssue>[]);
        }

        if (normalizedProjectIds.length == 1) {
          query = query.where(
            'projectId',
            isEqualTo: normalizedProjectIds.first,
          );
        } else if (normalizedProjectIds.length <= 30) {
          query = query.where('projectId', whereIn: normalizedProjectIds);
        } else {
          return _watchIssuesForProjectChunks(
            normalizedProjectIds,
            status: status,
          );
        }
      }
    }

    if (projectId == null &&
        projectIds == null &&
        organizationId != null &&
        organizationId.trim().isNotEmpty) {
      query = query.where('organizationId', isEqualTo: organizationId.trim());
    }

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    return query.snapshots().map((snapshot) {
      final issues = snapshot.docs.map(ProjectIssue.fromFirestore).toList();
      _sortIssues(issues);
      return issues;
    });
  }

  Stream<List<ProjectIssue>> _watchIssuesForProjectChunks(
    List<String> projectIds, {
    ProjectIssueStatus? status,
  }) {
    final chunks = <List<String>>[];
    for (var start = 0; start < projectIds.length; start += 30) {
      final end = start + 30 > projectIds.length
          ? projectIds.length
          : start + 30;
      chunks.add(projectIds.sublist(start, end));
    }

    late StreamController<List<ProjectIssue>> controller;
    final latestIssues = List<List<ProjectIssue>?>.filled(chunks.length, null);
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitMergedIssues() {
      if (latestIssues.any((issues) => issues == null)) {
        return;
      }

      final mergedIssues = latestIssues.expand((issues) => issues!).toList();
      _sortIssues(mergedIssues);
      controller.add(mergedIssues);
    }

    controller = StreamController<List<ProjectIssue>>(
      onListen: () {
        for (var index = 0; index < chunks.length; index += 1) {
          var query = _issues.where('projectId', whereIn: chunks[index]);

          if (status != null) {
            query = query.where('status', isEqualTo: status.name);
          }

          final subscription = query.snapshots().listen((snapshot) {
            latestIssues[index] = snapshot.docs
                .map(ProjectIssue.fromFirestore)
                .toList();
            emitMergedIssues();
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

  Stream<ProjectIssue?> watchIssue(String issueId) {
    return _issueDoc(issueId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }

      return ProjectIssue.fromFirestore(snapshot);
    });
  }

  Future<void> addIssue(ProjectIssue issue) async {
    final doc = issue.id.isEmpty ? _issues.doc() : _issues.doc(issue.id);
    final counterDoc = _issueCounters.doc(issue.projectId);
    final now = DateTime.now();

    await _firestore.runTransaction((transaction) async {
      final counterSnapshot = await transaction.get(counterDoc);
      final counterData = counterSnapshot.data();
      final nextNumber =
          counterData?['nextNumber'] as int? ??
          ((counterData?['lastNumber'] as int?) ?? 0) + 1;

      issue.id = doc.id;
      issue.issueNumber ??= nextNumber;
      issue.createdAt = now;
      issue.updatedAt = now;

      transaction.set(doc, issue.toFirestore());
      transaction.set(counterDoc, {
        'projectId': issue.projectId,
        'nextNumber': (issue.issueNumber ?? nextNumber) + 1,
        'lastNumber': issue.issueNumber,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    });
  }

  Future<void> updateIssue(ProjectIssue issue) async {
    issue.updatedAt = DateTime.now();
    await _issueDoc(issue.id).update(issue.toFirestore());
  }

  Future<void> setIssueStatus({
    required ProjectIssue issue,
    required ProjectIssueStatus status,
  }) async {
    final now = DateTime.now();

    await _issueDoc(issue.id).update({
      'status': status.name,
      'isOpen': status == ProjectIssueStatus.open,
      'closedAt': status == ProjectIssueStatus.closed
          ? Timestamp.fromDate(now)
          : null,
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  Future<void> deleteIssue(String issueId) async {
    await _issueDoc(issueId).delete();
  }

  Future<void> deleteIssuesByProjectId(String projectId) async {
    final snapshot = await _issues
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

  Future<void> deleteIssuesByOrganizationId(String organizationId) async {
    final snapshot = await _issues
        .where('organizationId', isEqualTo: organizationId)
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

  static void _sortIssues(List<ProjectIssue> issues) {
    issues.sort((a, b) {
      if (a.isOpen != b.isOpen) {
        return a.isOpen ? -1 : 1;
      }

      return b.updatedAt.compareTo(a.updatedAt);
    });
  }
}
