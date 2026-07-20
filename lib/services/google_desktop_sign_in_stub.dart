import 'package:firebase_auth/firebase_auth.dart';

Future<OAuthCredential> signInWithGoogleDesktop({required String clientId}) {
  throw FirebaseAuthException(
    code: 'google-sign-in-unsupported-platform',
    message: 'Desktop Google sign-in is unavailable on this platform.',
  );
}
