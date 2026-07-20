import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:taskman/services/google_desktop_sign_in.dart';

class AuthRepository {
  AuthRepository({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  Future<void>? _googleSignInInitialization;

  GoogleSignIn get _googleSignIn => GoogleSignIn.instance;

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

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      return _firebaseAuth.signInWithPopup(GoogleAuthProvider());
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      const desktopClientId = String.fromEnvironment(
        'GOOGLE_DESKTOP_CLIENT_ID',
      );
      const desktopClientSecret = String.fromEnvironment(
        'GOOGLE_DESKTOP_CLIENT_SECRET',
      );
      final credential = await signInWithGoogleDesktop(
        clientId: desktopClientId,
        clientSecret: desktopClientSecret,
      );
      return _firebaseAuth.signInWithCredential(credential);
    }

    try {
      await _ensureGoogleSignInInitialized();

      if (!_googleSignIn.supportsAuthenticate()) {
        throw FirebaseAuthException(
          code: 'google-sign-in-unsupported-platform',
          message: 'Google sign-in is unavailable on this platform.',
        );
      }

      final googleUser = await _googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google Sign-In did not return an ID token.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return _firebaseAuth.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw FirebaseAuthException(
          code: 'google-sign-in-cancelled',
          message: error.description,
        );
      }

      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw FirebaseAuthException(
          code: 'google-sign-in-configuration-error',
          message: error.description,
        );
      }

      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: error.description,
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _firebaseAuth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    final signedInWithGoogle =
        currentFirebaseUser?.providerData.any(
          (info) => info.providerId == GoogleAuthProvider.GOOGLE_SIGN_IN_METHOD,
        ) ??
        false;

    await _firebaseAuth.signOut();

    if (signedInWithGoogle &&
        !kIsWeb &&
        defaultTargetPlatform != TargetPlatform.windows) {
      try {
        await _ensureGoogleSignInInitialized();
        await _googleSignIn.signOut();
      } on GoogleSignInException {
        // Firebase is already signed out. Google cleanup is best-effort.
      }
    }
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

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInitialization ??= _googleSignIn.initialize();
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
