import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:taskman/repositories/auth_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/app_user.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    AuthRepository? authRepository,
    UserRepository? userRepository,
  }) : _authRepository = authRepository ?? AuthRepository(),
       _userRepository = userRepository ?? UserRepository() {
    _authSubscription = _authRepository.authStateChanges.listen(
      _handleAuthUser,
      onError: _handleAuthError,
    );
  }

  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  StreamSubscription<firebase_auth.User?>? _authSubscription;
  StreamSubscription<AppUser>? _profileSubscription;

  firebase_auth.User? _firebaseUser;
  AppUser _currentUser = AppUser.local();
  bool _isReady = false;
  bool _isLoadingProfile = false;
  Object? _lastError;

  firebase_auth.User? get firebaseUser => _firebaseUser;
  AppUser get currentUser => _currentUser;
  bool get isReady => _isReady;
  bool get isLoadingProfile => _isLoadingProfile;
  bool get isSignedIn => _firebaseUser != null;
  bool get isEmailPasswordUser =>
      _firebaseUser?.providerData.any(
        (info) => info.providerId == 'password',
      ) ??
      false;
  bool get isEmailVerified => _firebaseUser?.emailVerified ?? false;
  bool get needsEmailVerification =>
      isSignedIn && isEmailPasswordUser && !isEmailVerified;
  Object? get lastError => _lastError;

  Future<void> signIn({required String email, required String password}) async {
    await _authRepository.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _authRepository.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;

    if (user == null) {
      throw StateError('FirebaseAuth did not return a user.');
    }

    final trimmedDisplayName = displayName.trim();
    if (trimmedDisplayName.isNotEmpty) {
      await user.updateDisplayName(trimmedDisplayName);
    }

    if (!user.emailVerified) {
      await user.sendEmailVerification();
    }

    await _userRepository.ensureUserProfile(
      user,
      displayNameOverride: trimmedDisplayName,
    );
  }

  Future<void> reloadCurrentUser() async {
    final user = _firebaseUser;
    if (user == null) {
      return;
    }

    await user.reload();
    _firebaseUser = _authRepository.currentFirebaseUser;
    notifyListeners();
  }

  Future<void> sendEmailVerification() async {
    final user = _firebaseUser;
    if (user == null || user.emailVerified) {
      return;
    }

    await user.sendEmailVerification();
  }

  Future<void> updateProfile({
    required String userId,
    required String displayName,
  }) async {
    final user = _firebaseUser;
    if (user == null) {
      throw StateError('Cannot update profile while signed out.');
    }

    await _userRepository.updateUserProfile(
      id: user.uid,
      userId: userId,
      displayName: displayName,
      email: user.email,
    );
    await user.updateDisplayName(displayName.trim());
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _authRepository.sendPasswordResetEmail(email);
  }

  Future<void> signOut() {
    return _authRepository.signOut();
  }

  Future<void> _handleAuthUser(firebase_auth.User? user) async {
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _firebaseUser = user;
    _lastError = null;

    if (user == null) {
      _currentUser = AppUser.local();
      _isReady = true;
      _isLoadingProfile = false;
      notifyListeners();
      return;
    }

    _isLoadingProfile = true;
    notifyListeners();

    try {
      final freshUser = await _reloadUser(user);
      _firebaseUser = freshUser;
      _currentUser = await _userRepository.ensureUserProfile(freshUser);
      _isReady = true;
      _isLoadingProfile = false;
      notifyListeners();

      _profileSubscription = _userRepository
          .watchUser(freshUser.uid)
          .listen(
            (profile) {
              _currentUser = profile;
              _lastError = null;
              notifyListeners();
            },
            onError: (Object error) {
              _lastError = error;
              notifyListeners();
            },
          );
    } catch (error) {
      _currentUser = AppUser.unknown(user.uid);
      _lastError = error;
      _isReady = true;
      _isLoadingProfile = false;
      notifyListeners();
    }
  }

  Future<firebase_auth.User> _reloadUser(firebase_auth.User user) async {
    await user.reload();
    return _authRepository.currentFirebaseUser ?? user;
  }

  void _handleAuthError(Object error) {
    _lastError = error;
    _isReady = true;
    _isLoadingProfile = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_profileSubscription?.cancel());
    super.dispose();
  }
}
