import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskman/systems/project.dart';

class DuplicateProjectNameException implements Exception {
  const DuplicateProjectNameException(this.name);

  final String name;

  @override
  String toString() {
    return 'Duplicate project name: $name';
  }
}

class ProjectRepository {
  ProjectRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _projects =>
      _firestore.collection('projects');

  CollectionReference<Map<String, dynamic>> _projectNameKeys(String ownerId) {
    return _firestore
        .collection('projectNameKeys')
        .doc(Uri.encodeComponent(ownerId))
        .collection('names');
  }

  DocumentReference<Map<String, dynamic>> _projectNameKeyDocument({
    required String ownerId,
    required String name,
  }) {
    return _projectNameKeys(
      ownerId,
    ).doc(Uri.encodeComponent(Project.normalizeNameKey(name)));
  }

  Stream<List<Project>> watchProjects() {
    return _projects.orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map(Project.fromFirestore)
          .where((project) => !project.isArchived)
          .toList();
    });
  }

  Future<void> addProject({
    required String name,
    String? description,
    String ownerId = 'local-user',
  }) async {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Project name must not be empty.',
      );
    }

    if (await existsProjectName(name: trimmedName, ownerId: ownerId)) {
      throw DuplicateProjectNameException(trimmedName);
    }

    final doc = _projects.doc();
    final nameKeyDoc = _projectNameKeyDocument(
      ownerId: ownerId,
      name: trimmedName,
    );
    final now = DateTime.now();
    final project = Project(
      id: doc.id,
      name: trimmedName,
      description: description,
      ownerId: ownerId,
      createdAt: now,
      updatedAt: now,
    );

    await _firestore.runTransaction((transaction) async {
      final existingNameKey = await transaction.get(nameKeyDoc);

      if (existingNameKey.exists) {
        throw DuplicateProjectNameException(trimmedName);
      }

      transaction.set(doc, project.toFirestore());
      transaction.set(nameKeyDoc, {
        'projectId': doc.id,
        'name': trimmedName,
        'ownerId': ownerId,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> updateProject(Project project) async {
    final trimmedName = project.name.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError.value(
        project.name,
        'project.name',
        'Project name must not be empty.',
      );
    }

    final projectDoc = _projects.doc(project.id);

    await _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(projectDoc);

      if (!currentSnapshot.exists) {
        throw StateError('Project ${project.id} does not exist.');
      }

      final currentProject = Project.fromFirestore(currentSnapshot);
      final oldNameKeyDoc = _projectNameKeyDocument(
        ownerId: currentProject.ownerId,
        name: currentProject.name,
      );
      final newNameKeyDoc = _projectNameKeyDocument(
        ownerId: project.ownerId,
        name: trimmedName,
      );

      if (oldNameKeyDoc.path != newNameKeyDoc.path) {
        final existingNameKey = await transaction.get(newNameKeyDoc);

        if (existingNameKey.exists &&
            existingNameKey.data()?['projectId'] != project.id) {
          throw DuplicateProjectNameException(trimmedName);
        }
      }

      final now = DateTime.now();
      project.name = trimmedName;
      project.updatedAt = now;

      transaction.update(projectDoc, project.toFirestore());

      if (oldNameKeyDoc.path != newNameKeyDoc.path) {
        transaction.delete(oldNameKeyDoc);
      }

      transaction.set(newNameKeyDoc, {
        'projectId': project.id,
        'name': trimmedName,
        'ownerId': project.ownerId,
        'createdAt': Timestamp.fromDate(currentProject.createdAt),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> archiveProject(Project project) async {
    final projectDoc = _projects.doc(project.id);

    await _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(projectDoc);

      if (!currentSnapshot.exists) {
        return;
      }

      final currentProject = Project.fromFirestore(currentSnapshot);
      final nameKeyDoc = _projectNameKeyDocument(
        ownerId: currentProject.ownerId,
        name: currentProject.name,
      );

      transaction.update(projectDoc, {
        'isArchived': true,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      transaction.delete(nameKeyDoc);
    });
  }

  Future<bool> existsProjectName({
    required String name,
    required String ownerId,
    String? excludeProjectId,
  }) async {
    final nameKey = Project.normalizeNameKey(name);
    final nameKeyDoc = await _projectNameKeyDocument(
      ownerId: ownerId,
      name: name,
    ).get();

    if (nameKeyDoc.exists &&
        nameKeyDoc.data()?['projectId'] != excludeProjectId) {
      return true;
    }

    final snapshot = await _projects.where('ownerId', isEqualTo: ownerId).get();

    return snapshot.docs.map(Project.fromFirestore).any((project) {
      if (project.id == excludeProjectId || project.isArchived) {
        return false;
      }

      return Project.normalizeNameKey(project.name) == nameKey;
    });
  }
}
