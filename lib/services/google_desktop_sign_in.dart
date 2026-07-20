import 'package:firebase_auth/firebase_auth.dart';

import 'google_desktop_sign_in_stub.dart'
    if (dart.library.io) 'google_desktop_sign_in_io.dart'
    as implementation;

Future<OAuthCredential> signInWithGoogleDesktop({
  required String clientId,
  required String clientSecret,
}) {
  return implementation.signInWithGoogleDesktop(
    clientId: clientId,
    clientSecret: clientSecret,
  );
}
