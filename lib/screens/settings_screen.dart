import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/auth_controller.dart';
import 'package:taskman/systems/auth_scope.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _windowChannel = MethodChannel('taskman/window');
  static const _defaultGanttPosition = 'topLeft';
  static const _customGanttPosition = 'custom';

  static const _ganttPositionOptions = <_GanttPositionOption>[
    _GanttPositionOption(value: 'topLeft', label: '左上'),
    _GanttPositionOption(value: 'topRight', label: '右上'),
    _GanttPositionOption(value: 'bottomLeft', label: '左下'),
    _GanttPositionOption(value: 'bottomRight', label: '右下'),
    _GanttPositionOption(value: _customGanttPosition, label: '自由配置'),
  ];

  String _ganttPosition = _defaultGanttPosition;
  String? _message;
  bool _messageIsError = true;
  bool _isPlacementModeActive = false;
  bool _isPlacementModeChanging = false;

  bool get _supportsNativeGantt =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _loadGanttPosition();
  }

  @override
  void dispose() {
    if (_supportsNativeGantt && _isPlacementModeActive) {
      _windowChannel
          .invokeMethod<void>('setNativeGanttPlacementMode', false)
          .ignore();
    }
    super.dispose();
  }

  Future<void> _loadGanttPosition() async {
    if (!_supportsNativeGantt) {
      return;
    }

    try {
      final position = await _windowChannel.invokeMethod<String>(
        'getNativeGanttPosition',
      );
      if (!mounted || position == null) {
        return;
      }

      setState(() {
        _ganttPosition = _isKnownPosition(position)
            ? position
            : _defaultGanttPosition;
        _isPlacementModeActive = false;
      });
    } on MissingPluginException {
      _setMessage('Windows 実行時のみ変更できます');
    } on PlatformException {
      _setMessage('小窓位置を読み込めませんでした');
    }
  }

  Future<void> _setGanttPosition(String? position) async {
    if (position == null || !_isKnownPosition(position)) {
      return;
    }

    setState(() {
      _ganttPosition = position;
      _message = null;
      _messageIsError = true;
      if (position != _customGanttPosition) {
        _isPlacementModeActive = false;
      }
    });

    if (!_supportsNativeGantt) {
      _setMessage('Windows 実行時のみ変更できます');
      return;
    }

    try {
      await _windowChannel.invokeMethod<void>(
        'setNativeGanttPosition',
        position,
      );
      if (position != _customGanttPosition) {
        await _windowChannel.invokeMethod<void>(
          'setNativeGanttPlacementMode',
          false,
        );
      }
    } on MissingPluginException {
      _setMessage('Windows 実行時のみ変更できます');
    } on PlatformException {
      _setMessage('小窓位置を変更できませんでした');
    }
  }

  bool _isKnownPosition(String position) {
    return _ganttPositionOptions.any((option) => option.value == position);
  }

  Future<void> _togglePlacementMode() async {
    if (_ganttPosition != _customGanttPosition) {
      return;
    }

    if (!_supportsNativeGantt) {
      _setMessage('Windows 実行時のみ変更できます');
      return;
    }

    final nextValue = !_isPlacementModeActive;
    setState(() {
      _isPlacementModeChanging = true;
      _message = null;
      _messageIsError = true;
    });

    try {
      await _windowChannel.invokeMethod<void>(
        'setNativeGanttPosition',
        _customGanttPosition,
      );
      await _windowChannel.invokeMethod<void>(
        'setNativeGanttPlacementMode',
        nextValue,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isPlacementModeActive = nextValue;
        _message = nextValue ? '配置モードを起動しました' : '配置を保存しました';
        _messageIsError = false;
      });
    } on MissingPluginException {
      _setMessage('Windows 実行時のみ変更できます');
    } on PlatformException {
      _setMessage('配置モードを変更できませんでした');
    } finally {
      if (mounted) {
        setState(() {
          _isPlacementModeChanging = false;
        });
      }
    }
  }

  void _setMessage(String message, {bool isError = true}) {
    if (!mounted) {
      return;
    }

    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _openProfileDialog(AuthController auth) async {
    final user = auth.currentUser;
    final displayNameController = TextEditingController(text: user.displayName);
    final userIdController = TextEditingController(text: user.userId);
    var isSaving = false;
    String? errorText;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> save() async {
                final displayName = displayNameController.text.trim();
                final userId = userIdController.text.trim();
                var shouldResetSaving = true;

                if (displayName.isEmpty) {
                  setDialogState(() {
                    errorText = '表示名を入力してください';
                  });
                  return;
                }

                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });

                try {
                  await auth.updateProfile(
                    userId: userId,
                    displayName: displayName,
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  shouldResetSaving = false;
                  Navigator.pop(dialogContext);
                } on DuplicateUserIdException {
                  setDialogState(() {
                    errorText = 'このユーザーIDは既に使われています';
                  });
                } on InvalidUserIdException {
                  setDialogState(() {
                    errorText = 'ユーザーIDは3-32文字の英数字・._-で入力してください';
                  });
                } catch (_) {
                  setDialogState(() {
                    errorText = 'プロフィールを更新できませんでした';
                  });
                } finally {
                  if (shouldResetSaving && dialogContext.mounted) {
                    setDialogState(() {
                      isSaving = false;
                    });
                  }
                }
              }

              return AlertDialog(
                title: const Text('プロフィール編集'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: displayNameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: '表示名',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: userIdController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => isSaving ? null : save(),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'ユーザーID',
                          helperText: '3-32文字 / 英数字・._-',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton.icon(
                    onPressed: isSaving ? null : save,
                    icon: isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      displayNameController.dispose();
      userIdController.dispose();
    }
  }

  Future<void> _confirmSignOut(AuthController auth) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('サインアウト'),
          content: const Text('現在のアカウントからサインアウトします。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.logout),
              label: const Text('サインアウト'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true) {
      return;
    }

    try {
      await auth.signOut();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('サインアウトに失敗しました')));
    }
  }

  Future<void> _copyAccountText(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$labelをコピーしました')));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final auth = AuthScope.maybeOf(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('設定', style: textTheme.headlineSmall),
        const SizedBox(height: 24),
        if (auth != null) ...[
          _AccountPanel(
            auth: auth,
            onEditProfile: () => _openProfileDialog(auth),
            onCopyUserId: () =>
                _copyAccountText(auth.currentUser.userId, 'ユーザーID'),
            onCopyQrValue: () => _copyAccountText(
              auth.currentUser.qrCodeValue ?? auth.currentUser.id,
              'QR値',
            ),
            onSignOut: () => _confirmSignOut(auth),
          ),
          const SizedBox(height: 24),
        ],
        Text('小窓ガント', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DropdownButtonFormField<String>(
                key: ValueKey(_ganttPosition),
                initialValue: _ganttPosition,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '表示位置',
                ),
                items: [
                  for (final option in _ganttPositionOptions)
                    DropdownMenuItem<String>(
                      value: option.value,
                      child: Text(option.label),
                    ),
                ],
                onChanged: _setGanttPosition,
              ),
            ),
            if (_ganttPosition == _customGanttPosition)
              FilledButton.icon(
                onPressed: _isPlacementModeChanging
                    ? null
                    : _togglePlacementMode,
                icon: _isPlacementModeChanging
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isPlacementModeActive ? Icons.check : Icons.open_with,
                      ),
                label: Text(_isPlacementModeActive ? '配置モードを終了' : '配置モードを起動'),
              ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            style: textTheme.bodySmall?.copyWith(
              color: _messageIsError
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _GanttPositionOption {
  const _GanttPositionOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.auth,
    required this.onEditProfile,
    required this.onCopyUserId,
    required this.onCopyQrValue,
    required this.onSignOut,
  });

  final AuthController auth;
  final VoidCallback onEditProfile;
  final VoidCallback onCopyUserId;
  final VoidCallback onCopyQrValue;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                child: Text(_userInitial(user)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email ?? 'メール未設定',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AccountValueRow(
            icon: Icons.alternate_email,
            label: 'ユーザーID',
            value: user.userId,
          ),
          const SizedBox(height: 8),
          _AccountValueRow(
            icon: Icons.qr_code_2,
            label: 'QR値',
            value: user.qrCodeValue ?? user.id,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onEditProfile,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('プロフィール編集'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyUserId,
                icon: const Icon(Icons.copy),
                label: const Text('IDコピー'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyQrValue,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('QR値コピー'),
              ),
              OutlinedButton.icon(
                onPressed: onSignOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                ),
                icon: const Icon(Icons.logout),
                label: const Text('サインアウト'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountValueRow extends StatelessWidget {
  const _AccountValueRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

String _userInitial(AppUser user) {
  final label = user.label.trim();
  if (label.isEmpty) {
    return '?';
  }

  return label.characters.first.toUpperCase();
}
