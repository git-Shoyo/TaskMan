import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthRepository {
  AuthRepository({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentFirebaseUser => _firebaseAuth.currentUser;

  bool get isMicrosoftAccountLinked {
    return currentFirebaseUser?.providerData.any(
          (info) =>
              info.providerId == MicrosoftAuthProvider.MICROSOFT_SIGN_IN_METHOD,
        ) ??
        false;
  }

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _firebaseAuth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() {
    return _firebaseAuth.signOut();
  }

  Future<UserCredential> linkMicrosoftPlannerAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('Cannot link Microsoft account while signed out.');
    }

    final provider = _microsoftPlannerProvider();

    if (isMicrosoftAccountLinked) {
      return _reauthenticateWithProvider(user, provider);
    }

    try {
      return await _linkWithProvider(user, provider);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'provider-already-linked') {
        return _reauthenticateWithProvider(user, provider);
      }
      rethrow;
    }
  }

  Future<UserCredential> reauthenticateMicrosoftPlannerAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('Cannot reauthenticate while signed out.');
    }

    return _reauthenticateWithProvider(user, _microsoftPlannerProvider());
  }

  Future<void> unlinkMicrosoftAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null || !isMicrosoftAccountLinked) {
      return;
    }

    await user.unlink(MicrosoftAuthProvider.MICROSOFT_SIGN_IN_METHOD);
  }

  MicrosoftAuthProvider _microsoftPlannerProvider() {
    return MicrosoftAuthProvider()
      ..addScope('User.Read')
      ..addScope('Tasks.Read')
      ..setCustomParameters({'tenant': 'organizations', 'prompt': 'consent'});
  }

  Future<UserCredential> _linkWithProvider(
    User user,
    MicrosoftAuthProvider provider,
  ) {
    if (kIsWeb) {
      return user.linkWithPopup(provider);
    }

    return user.linkWithProvider(provider);
  }

  Future<UserCredential> _reauthenticateWithProvider(
    User user,
    MicrosoftAuthProvider provider,
  ) {
    if (kIsWeb) {
      return user.reauthenticateWithPopup(provider);
    }

    return user.reauthenticateWithProvider(provider);
  }
}
