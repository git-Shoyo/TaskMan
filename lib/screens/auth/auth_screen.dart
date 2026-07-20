import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taskman/systems/auth_scope.dart';

enum AuthScreenMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.initialMode = AuthScreenMode.signIn,
    this.onBack,
  });

  final AuthScreenMode initialMode;
  final VoidCallback? onBack;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  late bool _isCreatingAccount;
  bool _isSubmitting = false;
  bool _isResettingPassword = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _isCreatingAccount = widget.initialMode == AuthScreenMode.signUp;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final auth = AuthScope.of(context);
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (_isCreatingAccount) {
        await auth.createAccount(
          email: email,
          password: password,
          displayName: _displayNameController.text.trim(),
        );
      } else {
        await auth.signIn(email: email, password: password);
      }
    } on FirebaseAuthException catch (error) {
      debugPrint('FirebaseAuthException: ${error.code} / ${error.message}');
      _showMessage(_authErrorMessage(error), isError: true);
    } on FirebaseException catch (error) {
      debugPrint(
        'FirebaseException: ${error.plugin} / ${error.code} / ${error.message}',
      );
      _showMessage(_firebaseErrorMessage(error), isError: true);
    } catch (error, stackTrace) {
      debugPrint('Auth submit failed: $error\n$stackTrace');
      _showMessage('認証処理に失敗しました: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('メールアドレスを入力してください', isError: true);
      return;
    }

    setState(() {
      _isResettingPassword = true;
    });

    try {
      await AuthScope.of(context).sendPasswordResetEmail(email);
      _showMessage('パスワード再設定メールを送信しました', isError: false);
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorMessage(error), isError: true);
    } catch (_) {
      _showMessage('再設定メールの送信に失敗しました', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isResettingPassword = false;
        });
      }
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
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.onBack != null) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: _isSubmitting ? null : widget.onBack,
                              tooltip: '戻る',
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.task_alt),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'TaskMan',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.login),
                              label: Text('ログイン'),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.person_add_alt_1),
                              label: Text('登録'),
                            ),
                          ],
                          selected: {_isCreatingAccount},
                          onSelectionChanged: _isSubmitting
                              ? null
                              : (selection) {
                                  setState(() {
                                    _isCreatingAccount = selection.first;
                                  });
                                },
                        ),
                        const SizedBox(height: 20),
                        if (_isCreatingAccount) ...[
                          TextFormField(
                            controller: _displayNameController,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: '表示名',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (value) {
                              if (!_isCreatingAccount) {
                                return null;
                              }

                              if (value == null || value.trim().isEmpty) {
                                return '表示名を入力してください';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'メールアドレス',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) {
                              return 'メールアドレスを入力してください';
                            }
                            if (!email.contains('@')) {
                              return 'メールアドレスの形式を確認してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: [
                            _isCreatingAccount
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: 'パスワード',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              tooltip: _obscurePassword ? '表示' : '非表示',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.isEmpty) {
                              return 'パスワードを入力してください';
                            }
                            if (_isCreatingAccount && password.length < 6) {
                              return '6文字以上で入力してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _isSubmitting ? null : _submit,
                            icon: _isSubmitting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _isCreatingAccount
                                        ? Icons.person_add_alt_1
                                        : Icons.login,
                                  ),
                            label: Text(_isCreatingAccount ? '登録' : 'ログイン'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _isSubmitting || _isResettingPassword
                              ? null
                              : _sendPasswordResetEmail,
                          icon: _isResettingPassword
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.key_outlined),
                          label: const Text('パスワード再設定'),
                        ),
                      ],
                    ),
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

String _authErrorMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'email-already-in-use':
      return 'このメールアドレスは既に使われています';
    case 'invalid-email':
      return 'メールアドレスの形式を確認してください';
    case 'operation-not-allowed':
      return 'メール/パスワード認証が Firebase Console で有効になっていません';
    case 'invalid-credential':
    case 'user-not-found':
    case 'wrong-password':
      return 'メールアドレスまたはパスワードが違います';
    case 'user-disabled':
      return 'このアカウントは無効化されています';
    case 'weak-password':
      return 'パスワードが弱すぎます';
    case 'network-request-failed':
      return 'ネットワーク接続を確認してください';
    case 'too-many-requests':
      return '試行回数が多すぎます。しばらく待ってください';
    case 'unknown':
      if ((error.message ?? '').toLowerCase().contains('internal error')) {
        return 'Firebase Authentication の設定がまだ有効になっていない可能性があります。Firebase Console で Authentication を開始し、Email/Password を有効化してください';
      }
      return 'Firebase Auth から unknown が返りました: ${error.message ?? '詳細なし'}';
    default:
      return '認証に失敗しました (${error.code}): ${error.message ?? '詳細なし'}';
  }
}

String _firebaseErrorMessage(FirebaseException error) {
  switch (error.code) {
    case 'permission-denied':
      return 'アカウントは作成されましたが、プロフィール保存が権限不足で失敗しました。Firestore ルールをデプロイしてください';
    case 'unavailable':
      return 'Firebase に接続できませんでした。ネットワーク接続を確認してください';
    case 'not-found':
      return 'Firebase の設定またはデータベースを確認してください (${error.plugin})';
    default:
      return 'Firebase 処理に失敗しました (${error.plugin}/${error.code})';
  }
}
