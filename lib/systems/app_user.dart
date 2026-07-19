import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  static const localUserId = 'local-user';

  final String id;
  final String userId;
  final String? email;
  final String displayName;
  final String? qrCodeValue;

  const AppUser({
    required this.id,
    required this.userId,
    required this.displayName,
    this.email,
    this.qrCodeValue,
  });

  AppUser copyWith({
    String? id,
    String? userId,
    String? email,
    String? displayName,
    String? qrCodeValue,
  }) {
    return AppUser(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      qrCodeValue: qrCodeValue ?? this.qrCodeValue,
    );
  }

  factory AppUser.local() {
    return const AppUser(
      id: localUserId,
      userId: localUserId,
      displayName: '自分',
    );
  }

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final userId = (data['userId'] as String?)?.trim();
    final displayName =
        (data['displayName'] as String?)?.trim() ??
        (data['name'] as String?)?.trim();
    final email = (data['email'] as String?)?.trim();

    return AppUser(
      id: doc.id,
      userId: userId == null || userId.isEmpty ? doc.id : userId,
      displayName: displayName == null || displayName.isEmpty
          ? (email == null || email.isEmpty ? doc.id : email)
          : displayName,
      email: email == null || email.isEmpty ? null : email,
      qrCodeValue: (data['qrCodeValue'] as String?)?.trim(),
    );
  }

  factory AppUser.unknown(String id) {
    return AppUser(id: id, userId: id, displayName: id);
  }

  String get label => displayName.trim().isEmpty ? userId : displayName;

  String get searchableSubtitle {
    final parts = [
      if (email != null && email!.isNotEmpty) email,
      if (userId.isNotEmpty) 'ID: $userId',
    ];

    return parts.join(' / ');
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userIdKey': normalizeSearchValue(userId),
      'email': email,
      'emailKey': normalizeSearchValue(email),
      'displayName': displayName,
      'qrCodeValue': qrCodeValue,
      'qrCodeKey': normalizeSearchValue(qrCodeValue),
    };
  }

  static String normalizeSearchValue(String? value) {
    return value?.trim().toLowerCase() ?? '';
  }

  static String readSearchValueFromQr(String rawValue) {
    final trimmed = rawValue.trim();

    if (trimmed.isEmpty) {
      return '';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'taskman') {
      final userId = uri.queryParameters['userId'];
      if (userId != null && userId.trim().isNotEmpty) {
        return userId.trim();
      }

      if (uri.host == 'user' && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last.trim();
      }
    }

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          for (final key in const ['userId', 'id', 'email']) {
            final value = decoded[key];
            if (value is String && value.trim().isNotEmpty) {
              return value.trim();
            }
          }
        }
      } catch (_) {
        return trimmed;
      }
    }

    return trimmed;
  }
}
