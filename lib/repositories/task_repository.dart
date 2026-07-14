import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskman/systems/task.dart';

class TaskRepository {
  TaskRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _firestore.collection('tasks');

  Stream<List<Task>> watchTasks({String? projectId}) {
    Query<Map<String, dynamic>> query = _tasks;

    if (projectId != null) {
      query = query.where('projectId', isEqualTo: projectId);
    }

    return query.snapshots().map((snapshot) {
      final tasks = snapshot.docs.map(Task.fromFirestore).toList();
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tasks;
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

  Future<void> deleteTask(String taskId) async {
    await _tasks.doc(taskId).delete();
  }
}
