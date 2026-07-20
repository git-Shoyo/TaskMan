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

  void _setCreatingAccount(bool value) {
    if (_isSubmitting || _isCreatingAccount == value) {
      return;
    }

    setState(() {
      _isCreatingAccount = value;
    });

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 48 : 20,
                    vertical: isWide ? 32 : 20,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight - (isWide ? 64 : 40),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(
                          onBack: widget.onBack,
                          isBusy: _isSubmitting,
                        ),
                        SizedBox(height: isWide ? 40 : 28),
                        if (isWide)
                          ExpandedAuthLayout(
                            form: _buildAuthCard(context),
                            isCreatingAccount: _isCreatingAccount,
                          )
                        else
                          Center(child: _buildAuthCard(context)),
                        SizedBox(height: isWide ? 24 : 20),
                        const _AuthFooter(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.10),
            blurRadius: 44,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Column(
                  key: ValueKey(_isCreatingAccount),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCreatingAccount
                          ? 'TaskManを始める'
                          : 'おかえりなさい',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isCreatingAccount
                          ? 'アカウントを作成して、課題とプロジェクトを整理しましょう。'
                          : '登録済みのメールアドレスでログインしてください。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _ModeSelector(
                isCreatingAccount: _isCreatingAccount,
                enabled: !_isSubmitting,
                onChanged: _setCreatingAccount,
              ),
              const SizedBox(height: 24),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _isCreatingAccount
                    ? Column(
                        children: [
                          TextFormField(
                            controller: _displayNameController,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: _inputDecoration(
                              context,
                              label: '表示名',
                              hint: '例：紺谷 之衣亜',
                              icon: Icons.badge_outlined,
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
                          const SizedBox(height: 14),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: _inputDecoration(
                  context,
                  label: 'メールアドレス',
                  hint: 'name@example.com',
                  icon: Icons.mail_outline_rounded,
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
              const SizedBox(height: 14),
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
                decoration: _inputDecoration(
                  context,
                  label: 'パスワード',
                  hint: _isCreatingAccount ? '6文字以上' : null,
                  icon: Icons.lock_outline_rounded,
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
              if (!_isCreatingAccount) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isSubmitting || _isResettingPassword
                        ? null
                        : _sendPasswordResetEmail,
                    child: _isResettingPassword
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('パスワードを忘れた場合'),
                  ),
                ),
              ] else
                const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _isSubmitting
                        ? const SizedBox.square(
                            key: ValueKey('loading'),
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Row(
                            key: ValueKey(_isCreatingAccount),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isCreatingAccount
                                    ? Icons.person_add_alt_1_rounded
                                    : Icons.login_rounded,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _isCreatingAccount
                                    ? 'アカウントを作成'
                                    : 'ログイン',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _isCreatingAccount
                    ? '登録すると、確認メールが送信されます。'
                    : 'ログイン情報はFirebase Authenticationで安全に処理されます。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.6,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: colorScheme.error,
          width: 1.6,
        ),
      ),
    );
  }
}

class ExpandedAuthLayout extends StatelessWidget {
  const ExpandedAuthLayout({
    super.key,
    required this.form,
    required this.isCreatingAccount,
  });

  final Widget form;
  final bool isCreatingAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 10,
          child: _AuthIntroduction(
            isCreatingAccount: isCreatingAccount,
          ),
        ),
        const SizedBox(width: 64),
        Expanded(
          flex: 9,
          child: Center(child: form),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.isBusy,
  });

  final VoidCallback? onBack;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        if (onBack != null) ...[
          IconButton.filledTonal(
            onPressed: isBusy ? null : onBack,
            tooltip: '戻る',
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 14),
        ],
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.task_alt_rounded,
            color: colorScheme.onPrimary,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'TaskMan',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class _AuthIntroduction extends StatelessWidget {
  const _AuthIntroduction({
    required this.isCreatingAccount,
  });

  final bool isCreatingAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: Column(
        key: ValueKey(isCreatingAccount),
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isCreatingAccount
                  ? '新しい学習管理を始める'
                  : '続きから取り組む',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isCreatingAccount
                ? '課題も予定も、\nひとつの場所へ。'
                : '今日やることに、\nすぐ戻れる。',
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 46,
              height: 1.14,
              letterSpacing: -1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 510),
            child: Text(
              isCreatingAccount
                  ? 'アカウントを作成すると、Windows・Android・Webの間で'
                      'タスクやプロジェクトを同期できます。'
                  : 'ログインすると、保存済みのタスク、プロジェクト、'
                      '予定を引き続き利用できます。',
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.75,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(
                icon: Icons.sync_rounded,
                label: '複数端末で同期',
              ),
              _InfoChip(
                icon: Icons.notifications_none_rounded,
                label: '期限を通知',
              ),
              _InfoChip(
                icon: Icons.timeline_rounded,
                label: '進捗を見える化',
              ),
            ],
          ),
          const SizedBox(height: 34),
          _SecurityNotice(isCreatingAccount: isCreatingAccount),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.isCreatingAccount,
    required this.enabled,
    required this.onChanged,
  });

  final bool isCreatingAccount;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'ログイン',
              icon: Icons.login_rounded,
              selected: !isCreatingAccount,
              enabled: enabled,
              onPressed: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeButton(
              label: '新規登録',
              icon: Icons.person_add_alt_1_rounded,
              selected: isCreatingAccount,
              enabled: enabled,
              onPressed: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({
    required this.isCreatingAccount,
  });

  final bool isCreatingAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 510),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isCreatingAccount
                  ? '登録後にメールアドレスの確認を行うことで、アカウントを保護します。'
                  : '認証情報はアプリ内に直接保存せず、Firebase Authenticationで管理します。',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.55,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -110,
            child: Container(
              width: 430,
              height: 430,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer.withValues(alpha: 0.42),
              ),
            ),
          ),
          Positioned(
            bottom: -220,
            left: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.36),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                color: colorScheme.outlineVariant.withValues(alpha: 0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 38.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _AuthFooter extends StatelessWidget {
  const _AuthFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      'TaskMan  •  Windows / Android / Web',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
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
        return 'Firebase Authentication の設定がまだ有効になっていない可能性があります。'
            'Firebase Console で Authentication を開始し、'
            'Email/Password を有効化してください';
      }
      return 'Firebase Auth から unknown が返りました: '
          '${error.message ?? '詳細なし'}';
    default:
      return '認証に失敗しました (${error.code}): '
          '${error.message ?? '詳細なし'}';
  }
}

String _firebaseErrorMessage(FirebaseException error) {
  switch (error.code) {
    case 'permission-denied':
      return 'アカウントは作成されましたが、プロフィール保存が権限不足で失敗しました。'
          'Firestore ルールをデプロイしてください';
    case 'unavailable':
      return 'Firebase に接続できませんでした。ネットワーク接続を確認してください';
    case 'not-found':
      return 'Firebase の設定またはデータベースを確認してください (${error.plugin})';
    default:
      return 'Firebase 処理に失敗しました (${error.plugin}/${error.code})';
  }
}
