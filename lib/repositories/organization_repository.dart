import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskman/systems/organization.dart';

class DuplicateOrganizationNameException implements Exception {
  const DuplicateOrganizationNameException(this.name);

  final String name;

  @override
  String toString() {
    return 'Duplicate organization name: $name';
  }
}

class OrganizationRepository {
  OrganizationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _organizations =>
      _firestore.collection('organizations');

  CollectionReference<Map<String, dynamic>> _organizationNameKeys(
    String ownerId,
  ) {
    return _firestore
        .collection('organizationNameKeys')
        .doc(Uri.encodeComponent(ownerId))
        .collection('names');
  }

  DocumentReference<Map<String, dynamic>> _organizationNameKeyDocument({
    required String ownerId,
    required String name,
  }) {
    return _organizationNameKeys(
      ownerId,
    ).doc(Uri.encodeComponent(Organization.normalizeNameKey(name)));
  }

  Stream<List<Organization>> watchOrganizations({String? memberId}) {
    Query<Map<String, dynamic>> query = _organizations;
    final normalizedMemberId = memberId?.trim();

    if (normalizedMemberId != null && normalizedMemberId.isNotEmpty) {
      query = query.where('memberIds', arrayContains: normalizedMemberId);
    }

    return query.snapshots().map((snapshot) {
      final organizations = snapshot.docs
          .map(Organization.fromFirestore)
          .where((organization) => !organization.isArchived)
          .toList();

      organizations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return organizations;
    });
  }

  Stream<Organization?> watchOrganization(String organizationId) {
    return _organizations.doc(organizationId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }

      final organization = Organization.fromFirestore(snapshot);
      return organization.isArchived ? null : organization;
    });
  }

  Future<void> addOrganization({
    required String name,
    String? description,
    String ownerId = 'local-user',
    List<String> memberIds = const [],
    Map<String, String> memberRoles = const {},
  }) async {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Organization name must not be empty.',
      );
    }

    if (await existsOrganizationName(name: trimmedName, ownerId: ownerId)) {
      throw DuplicateOrganizationNameException(trimmedName);
    }

    final doc = _organizations.doc();
    final nameKeyDoc = _organizationNameKeyDocument(
      ownerId: ownerId,
      name: trimmedName,
    );
    final now = DateTime.now();
    final normalizedMemberIds = <String>{
      ownerId,
      ...memberIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    }.toList();
    final normalizedMemberRoles = <String, String>{
      for (final memberId in normalizedMemberIds)
        memberId: memberId == ownerId ? 'owner' : 'member',
      ...memberRoles,
      ownerId: 'owner',
    };
    final organization = Organization(
      id: doc.id,
      name: trimmedName,
      description: description,
      ownerId: ownerId,
      memberIds: normalizedMemberIds,
      memberRoles: normalizedMemberRoles,
      createdAt: now,
      updatedAt: now,
    );

    await _firestore.runTransaction((transaction) async {
      final existingNameKey = await transaction.get(nameKeyDoc);

      if (existingNameKey.exists) {
        throw DuplicateOrganizationNameException(trimmedName);
      }

      transaction.set(doc, organization.toFirestore());
      transaction.set(nameKeyDoc, {
        'organizationId': doc.id,
        'name': trimmedName,
        'ownerId': ownerId,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> updateOrganization(Organization organization) async {
    final trimmedName = organization.name.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError.value(
        organization.name,
        'organization.name',
        'Organization name must not be empty.',
      );
    }

    final organizationDoc = _organizations.doc(organization.id);

    await _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(organizationDoc);

      if (!currentSnapshot.exists) {
        throw StateError('Organization ${organization.id} does not exist.');
      }

      final currentOrganization = Organization.fromFirestore(currentSnapshot);
      final oldNameKeyDoc = _organizationNameKeyDocument(
        ownerId: currentOrganization.ownerId,
        name: currentOrganization.name,
      );
      final newNameKeyDoc = _organizationNameKeyDocument(
        ownerId: organization.ownerId,
        name: trimmedName,
      );

      if (oldNameKeyDoc.path != newNameKeyDoc.path) {
        final existingNameKey = await transaction.get(newNameKeyDoc);

        if (existingNameKey.exists &&
            existingNameKey.data()?['organizationId'] != organization.id) {
          throw DuplicateOrganizationNameException(trimmedName);
        }
      }

      final now = DateTime.now();
      organization.name = trimmedName;
      organization.updatedAt = now;

      transaction.update(organizationDoc, organization.toFirestore());

      if (oldNameKeyDoc.path != newNameKeyDoc.path) {
        transaction.delete(oldNameKeyDoc);
      }

      transaction.set(newNameKeyDoc, {
        'organizationId': organization.id,
        'name': trimmedName,
        'ownerId': organization.ownerId,
        'createdAt': Timestamp.fromDate(currentOrganization.createdAt),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> archiveOrganization(Organization organization) async {
    final organizationDoc = _organizations.doc(organization.id);

    await _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(organizationDoc);

      if (!currentSnapshot.exists) {
        return;
      }

      final currentOrganization = Organization.fromFirestore(currentSnapshot);
      final nameKeyDoc = _organizationNameKeyDocument(
        ownerId: currentOrganization.ownerId,
        name: currentOrganization.name,
      );

      transaction.update(organizationDoc, {
        'isArchived': true,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      transaction.delete(nameKeyDoc);
    });
  }

  Future<bool> existsOrganizationName({
    required String name,
    required String ownerId,
    String? excludeOrganizationId,
  }) async {
    final nameKeyDoc = await _organizationNameKeyDocument(
      ownerId: ownerId,
      name: name,
    ).get();

    return nameKeyDoc.exists &&
        nameKeyDoc.data()?['organizationId'] != excludeOrganizationId;
  }
}
