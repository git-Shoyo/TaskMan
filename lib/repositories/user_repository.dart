import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/organization.dart';
import 'package:taskman/systems/project.dart';

enum UserSearchField { email, userId, qrCode }

class DuplicateUserIdException implements Exception {
  const DuplicateUserIdException(this.userId);

  final String userId;

  @override
  String toString() {
    return 'Duplicate user id: $userId';
  }
}

class InvalidUserIdException implements Exception {
  const InvalidUserIdException(this.userId);

  final String userId;

  @override
  String toString() {
    return 'Invalid user id: $userId';
  }
}

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _userIdKeys =>
      _firestore.collection('userIdKeys');

  DocumentReference<Map<String, dynamic>> _userIdKeyDocument(String userId) {
    return _userIdKeys.doc(Uri.encodeComponent(_normalizeUserIdKey(userId)));
  }

  Stream<AppUser> watchUser(String id) {
    return _users.doc(id).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return AppUser.unknown(id);
      }

      return AppUser.fromFirestore(snapshot);
    });
  }

  Stream<List<AppUser>> watchUsersByIds(Iterable<String> ids) {
    final uniqueIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (uniqueIds.isEmpty) {
      return Stream.value(const <AppUser>[]);
    }

    final usersById = <String, AppUser>{};
    final pendingRemoteIds = uniqueIds
        .where((id) => id != AppUser.localUserId)
        .toSet();
    late StreamController<List<AppUser>> controller;
    final subscriptions =
        <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];

    void emitUsersIfReady() {
      if (pendingRemoteIds.isNotEmpty || controller.isClosed) {
        return;
      }

      controller.add(
        uniqueIds.map((id) => usersById[id] ?? AppUser.unknown(id)).toList(),
      );
    }

    controller = StreamController<List<AppUser>>(
      onListen: () {
        if (uniqueIds.contains(AppUser.localUserId)) {
          usersById[AppUser.localUserId] = AppUser.local();
        }

        for (final id in pendingRemoteIds.toList()) {
          final subscription = _users.doc(id).snapshots().listen((snapshot) {
            usersById[id] = snapshot.exists
                ? AppUser.fromFirestore(snapshot)
                : AppUser.unknown(id);
            pendingRemoteIds.remove(id);
            emitUsersIfReady();
          }, onError: controller.addError);
          subscriptions.add(subscription);
        }

        emitUsersIfReady();
      },
      onCancel: () async {
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      },
    );

    return controller.stream;
  }

  Future<AppUser> ensureUserProfile(
    firebase_auth.User firebaseUser, {
    String? displayNameOverride,
  }) async {
    final userDoc = _users.doc(firebaseUser.uid);
    final now = DateTime.now();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userDoc);
      final email = _emptyToNull(firebaseUser.email);
      final displayName = _defaultDisplayName(
        firebaseUser,
        displayNameOverride: displayNameOverride,
      );

      if (snapshot.exists) {
        final currentUser = AppUser.fromFirestore(snapshot);
        final userIdKeyDoc = _userIdKeyDocument(currentUser.userId);
        final userIdKeySnapshot = await transaction.get(userIdKeyDoc);
        final shouldUpdateDisplayName =
            (displayNameOverride?.trim().isNotEmpty ?? false) ||
            currentUser.displayName.trim().isEmpty;

        transaction.set(userDoc, {
          'email': email,
          'emailKey': AppUser.normalizeSearchValue(email),
          if (shouldUpdateDisplayName) 'displayName': displayName,
          if ((currentUser.qrCodeValue ?? '').trim().isEmpty)
            'qrCodeValue': _qrCodeValue(firebaseUser.uid),
          if ((currentUser.qrCodeValue ?? '').trim().isEmpty)
            'qrCodeKey': AppUser.normalizeSearchValue(
              _qrCodeValue(firebaseUser.uid),
            ),
          'updatedAt': Timestamp.fromDate(now),
        }, SetOptions(merge: true));

        if (!userIdKeySnapshot.exists ||
            userIdKeySnapshot.data()?['uid'] == firebaseUser.uid) {
          transaction.set(userIdKeyDoc, {
            'uid': firebaseUser.uid,
            'userId': currentUser.userId,
            'userIdKey': _normalizeUserIdKey(currentUser.userId),
            'updatedAt': Timestamp.fromDate(now),
          }, SetOptions(merge: true));
        }
        return;
      }

      final appUser = AppUser(
        id: firebaseUser.uid,
        userId: firebaseUser.uid,
        email: email,
        displayName: displayName,
        qrCodeValue: _qrCodeValue(firebaseUser.uid),
      );
      final userIdKeyDoc = _userIdKeyDocument(appUser.userId);
      final userIdKeySnapshot = await transaction.get(userIdKeyDoc);

      if (userIdKeySnapshot.exists &&
          userIdKeySnapshot.data()?['uid'] != firebaseUser.uid) {
        throw DuplicateUserIdException(appUser.userId);
      }

      transaction.set(userDoc, {
        ...appUser.toFirestore(),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      transaction.set(userIdKeyDoc, {
        'uid': firebaseUser.uid,
        'userId': appUser.userId,
        'userIdKey': _normalizeUserIdKey(appUser.userId),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    final snapshot = await userDoc.get();
    return snapshot.exists
        ? AppUser.fromFirestore(snapshot)
        : AppUser.unknown(firebaseUser.uid);
  }

  Future<void> updateUserProfile({
    required String id,
    required String userId,
    required String displayName,
    String? email,
  }) async {
    final trimmedUserId = userId.trim();
    final trimmedDisplayName = displayName.trim();

    if (!_isValidUserId(trimmedUserId)) {
      throw InvalidUserIdException(trimmedUserId);
    }

    if (trimmedDisplayName.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Display name must not be empty.',
      );
    }

    final userDoc = _users.doc(id);
    final now = DateTime.now();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userDoc);
      final currentUser = snapshot.exists
          ? AppUser.fromFirestore(snapshot)
          : AppUser.unknown(id);
      final oldUserIdKeyDoc = _userIdKeyDocument(currentUser.userId);
      final newUserIdKeyDoc = _userIdKeyDocument(trimmedUserId);

      if (oldUserIdKeyDoc.path != newUserIdKeyDoc.path) {
        final existingUserIdKey = await transaction.get(newUserIdKeyDoc);

        if (existingUserIdKey.exists &&
            existingUserIdKey.data()?['uid'] != id) {
          throw DuplicateUserIdException(trimmedUserId);
        }
      }

      transaction.set(userDoc, {
        'userId': trimmedUserId,
        'userIdKey': _normalizeUserIdKey(trimmedUserId),
        'displayName': trimmedDisplayName,
        'email': _emptyToNull(email),
        'emailKey': AppUser.normalizeSearchValue(email),
        'qrCodeValue': _qrCodeValue(id),
        'qrCodeKey': AppUser.normalizeSearchValue(_qrCodeValue(id)),
        if (!snapshot.exists) 'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      if (oldUserIdKeyDoc.path != newUserIdKeyDoc.path) {
        transaction.delete(oldUserIdKeyDoc);
      }

      transaction.set(newUserIdKeyDoc, {
        'uid': id,
        'userId': trimmedUserId,
        'userIdKey': _normalizeUserIdKey(trimmedUserId),
        if (oldUserIdKeyDoc.path != newUserIdKeyDoc.path)
          'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    });
  }

  Future<List<AppUser>> fetchProjectMembers(Project project) async {
    final ids = <String>{
      if (project.ownerId.trim().isNotEmpty) project.ownerId.trim(),
      ...project.memberIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    };

    if (ids.isEmpty) {
      ids.add(AppUser.localUserId);
    }

    return fetchUsersByIds(ids.toList());
  }

  Future<List<AppUser>> fetchOrganizationMembers(
    Organization organization,
  ) async {
    final ids = <String>{
      if (organization.ownerId.trim().isNotEmpty) organization.ownerId.trim(),
      ...organization.memberIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
    };

    if (ids.isEmpty) {
      ids.add(AppUser.localUserId);
    }

    return fetchUsersByIds(ids.toList());
  }

  Future<List<AppUser>> fetchUsersByIds(List<String> ids) async {
    final uniqueIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (uniqueIds.isEmpty) {
      return [AppUser.local()];
    }

    final usersById = <String, AppUser>{};

    if (uniqueIds.contains(AppUser.localUserId)) {
      usersById[AppUser.localUserId] = AppUser.local();
    }

    final remoteIds = uniqueIds
        .where((id) => id != AppUser.localUserId)
        .toList();
    final snapshots = await Future.wait(
      remoteIds.map((id) => _users.doc(id).get()),
    );

    for (var index = 0; index < remoteIds.length; index += 1) {
      final snapshot = snapshots[index];
      usersById[remoteIds[index]] = snapshot.exists
          ? AppUser.fromFirestore(snapshot)
          : AppUser.unknown(remoteIds[index]);
    }

    return uniqueIds.map((id) => usersById[id] ?? AppUser.unknown(id)).toList();
  }

  Future<List<AppUser>> searchUsers({
    required String query,
    required UserSearchField field,
  }) async {
    final trimmedQuery = query.trim();
    final rawValue = field == UserSearchField.qrCode
        ? AppUser.readSearchValueFromQr(trimmedQuery)
        : trimmedQuery;
    final normalizedValue = AppUser.normalizeSearchValue(rawValue);
    final normalizedQuery = AppUser.normalizeSearchValue(trimmedQuery);

    if (normalizedValue.isEmpty) {
      return [];
    }

    final usersById = <String, AppUser>{};

    Future<void> addQuery(
      Query<Map<String, dynamic>> query, {
      int limit = 10,
    }) async {
      final snapshot = await query.limit(limit).get();
      for (final doc in snapshot.docs) {
        usersById[doc.id] = AppUser.fromFirestore(doc);
      }
    }

    Future<void> addDocById(String id) async {
      if (id.contains('/')) {
        return;
      }

      final snapshot = await _users.doc(id).get();
      if (snapshot.exists) {
        usersById[snapshot.id] = AppUser.fromFirestore(snapshot);
      }
    }

    switch (field) {
      case UserSearchField.email:
        await Future.wait([
          addQuery(_users.where('emailKey', isEqualTo: normalizedValue)),
          addQuery(_users.where('email', isEqualTo: rawValue)),
        ]);
      case UserSearchField.userId:
        await Future.wait([
          addQuery(_users.where('userIdKey', isEqualTo: normalizedValue)),
          addQuery(_users.where('userId', isEqualTo: rawValue)),
          addDocById(rawValue),
        ]);
      case UserSearchField.qrCode:
        await Future.wait([
          addQuery(_users.where('qrCodeKey', isEqualTo: normalizedValue)),
          if (normalizedQuery != normalizedValue)
            addQuery(_users.where('qrCodeKey', isEqualTo: normalizedQuery)),
          addQuery(_users.where('qrCodeValue', isEqualTo: trimmedQuery)),
          addQuery(_users.where('userIdKey', isEqualTo: normalizedValue)),
          addQuery(_users.where('userId', isEqualTo: rawValue)),
          addQuery(_users.where('emailKey', isEqualTo: normalizedValue)),
          addQuery(_users.where('email', isEqualTo: rawValue)),
          addDocById(rawValue),
        ]);
    }

    return usersById.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  static String _defaultDisplayName(
    firebase_auth.User firebaseUser, {
    String? displayNameOverride,
  }) {
    final explicitName = displayNameOverride?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }

    final authName = firebaseUser.displayName?.trim();
    if (authName != null && authName.isNotEmpty) {
      return authName;
    }

    final email = firebaseUser.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return '自分';
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static bool _isValidUserId(String userId) {
    return RegExp(r'^[a-zA-Z0-9._-]{3,32}$').hasMatch(userId);
  }

  static String _normalizeUserIdKey(String userId) {
    return userId.trim().toLowerCase();
  }

  static String _qrCodeValue(String uid) {
    return 'taskman://user/$uid';
  }
}
