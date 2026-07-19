import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taskman/systems/auth_scope.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isSending = false;

  Future<void> _checkVerification() async {
    setState(() {
      _isChecking = true;
    });

    try {
      await AuthScope.of(context).reloadCurrentUser();
      if (!mounted) {
        return;
      }

      final auth = AuthScope.of(context);
      if (auth.needsEmailVerification) {
        _showMessage('まだメール確認が完了していません', isError: true);
      }
    } catch (_) {
      _showMessage('確認状態を更新できませんでした', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isSending = true;
    });

    try {
      await AuthScope.of(context).sendEmailVerification();
      _showMessage('確認メールを送信しました', isError: false);
    } on FirebaseAuthException catch (error) {
      _showMessage(_verificationErrorMessage(error), isError: true);
    } catch (_) {
      _showMessage('確認メールを送信できませんでした', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await AuthScope.of(context).signOut();
    } catch (_) {
      _showMessage('サインアウトに失敗しました', isError: true);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final email = auth.firebaseUser?.email ?? '登録したメールアドレス';
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: const Icon(Icons.mark_email_unread_outlined),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'メールを確認してください',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$email に確認メールを送信しました。リンクを開いたあと、下のボタンで確認状態を更新してください。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isChecking ? null : _checkVerification,
                        icon: _isChecking
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.verified_outlined),
                        label: const Text('確認したので続行'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isSending ? null : _resendEmail,
                        icon: _isSending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.outgoing_mail),
                        label: const Text('確認メールを再送'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('別のアカウントでログイン'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _verificationErrorMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'too-many-requests':
      return '送信回数が多すぎます。しばらく待ってください';
    case 'network-request-failed':
      return 'ネットワーク接続を確認してください';
    default:
      return '確認メールを送信できませんでした (${error.code})';
  }
}
