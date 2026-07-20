import 'package:firebase_auth/firebase_auth.dart';

Future<OAuthCredential> signInWithGoogleDesktop({
  required String clientId,
  required String clientSecret,
}) {
  throw FirebaseAuthException(
    code: 'google-sign-in-unsupported-platform',
    message: 'Desktop Google sign-in is unavailable on this platform.',
  );
}
