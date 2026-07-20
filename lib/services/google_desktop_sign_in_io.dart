import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const _authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
const _signInTimeout = Duration(minutes: 2);

Future<OAuthCredential> signInWithGoogleDesktop({
  required String clientId,
  required String clientSecret,
}) async {
  final normalizedClientId = clientId.trim();
  final normalizedClientSecret = clientSecret.trim();
  if (normalizedClientId.isEmpty) {
    throw FirebaseAuthException(
      code: 'google-desktop-client-id-missing',
      message: 'GOOGLE_DESKTOP_CLIENT_ID is not configured.',
    );
  }
  if (normalizedClientSecret.isEmpty) {
    throw FirebaseAuthException(
      code: 'google-desktop-client-secret-missing',
      message: 'GOOGLE_DESKTOP_CLIENT_SECRET is not configured.',
    );
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final redirectUri = Uri.parse('http://127.0.0.1:${server.port}/');
  final state = _randomUrlSafeString(32);
  final codeVerifier = _randomUrlSafeString(64);
  final codeChallenge = _base64UrlWithoutPadding(
    sha256.convert(utf8.encode(codeVerifier)).bytes,
  );

  final authorizationUri = Uri.parse(_authorizationEndpoint).replace(
    queryParameters: {
      'client_id': normalizedClientId,
      'redirect_uri': redirectUri.toString(),
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'select_account',
    },
  );

  try {
    final launched = await launchUrl(
      authorizationUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw FirebaseAuthException(
        code: 'google-desktop-browser-failed',
        message: 'Could not launch the default browser.',
      );
    }

    late final HttpRequest request;
    try {
      request = await server.first.timeout(_signInTimeout);
    } on TimeoutException {
      throw FirebaseAuthException(
        code: 'google-desktop-timeout',
        message: 'Google sign-in timed out.',
      );
    }

    final query = request.uri.queryParameters;
    if (query['state'] != state) {
      await _respondToBrowser(
        request,
        title: '認証に失敗しました',
        message: '応答を検証できませんでした。TaskManに戻って再試行してください。',
      );
      throw FirebaseAuthException(
        code: 'google-desktop-state-mismatch',
        message: 'OAuth state did not match.',
      );
    }

    final oauthError = query['error'];
    if (oauthError != null) {
      await _respondToBrowser(
        request,
        title: '認証を完了できませんでした',
        message: 'TaskManに戻って再試行してください。',
      );

      if (oauthError == 'access_denied') {
        throw FirebaseAuthException(
          code: 'google-sign-in-cancelled',
          message: query['error_description'] ?? oauthError,
        );
      }

      throw FirebaseAuthException(
        code: 'google-desktop-oauth-error',
        message: query['error_description'] ?? oauthError,
      );
    }

    final authorizationCode = query['code'];
    if (authorizationCode == null || authorizationCode.isEmpty) {
      await _respondToBrowser(
        request,
        title: '認証に失敗しました',
        message: '認証コードを取得できませんでした。',
      );
      throw FirebaseAuthException(
        code: 'google-desktop-oauth-error',
        message: 'Authorization code was not returned.',
      );
    }

    final tokenResponse = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': normalizedClientId,
        'client_secret': normalizedClientSecret,
        'code': authorizationCode,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri.toString(),
      },
    );

    Map<String, dynamic> tokenBody;
    try {
      tokenBody = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    } on FormatException {
      throw FirebaseAuthException(
        code: 'google-desktop-token-error',
        message: 'Google returned an invalid token response.',
      );
    }

    if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
      throw FirebaseAuthException(
        code: 'google-desktop-token-error',
        message:
            tokenBody['error_description']?.toString() ??
            tokenBody['error']?.toString() ??
            'HTTP ${tokenResponse.statusCode}',
      );
    }

    final idToken = tokenBody['id_token']?.toString();
    final accessToken = tokenBody['access_token']?.toString();
    if ((idToken == null || idToken.isEmpty) &&
        (accessToken == null || accessToken.isEmpty)) {
      throw FirebaseAuthException(
        code: 'google-desktop-token-error',
        message: 'No ID token or access token was returned.',
      );
    }

    await _respondToBrowser(
      request,
      title: 'TaskManへのログインが完了しました',
      message: 'このタブを閉じてTaskManに戻ってください。',
    );

    return GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );
  } finally {
    await server.close(force: true);
  }
}

Future<void> _respondToBrowser(
  HttpRequest request, {
  required String title,
  required String message,
}) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.html;
  request.response.write('''
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
</head>
<body style="font-family: sans-serif; padding: 48px; line-height: 1.7;">
  <h1>$title</h1>
  <p>$message</p>
</body>
</html>
''');
  await request.response.close();
}

String _randomUrlSafeString(int byteLength) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return _base64UrlWithoutPadding(bytes);
}

String _base64UrlWithoutPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}
