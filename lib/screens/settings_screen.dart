import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/microsoft_integration_repository.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/auth_controller.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/microsoft_integration.dart';
import 'package:taskman/systems/project.dart';
import 'package:url_launcher/url_launcher.dart';

final DateFormat _settingsDateTimeFormat = DateFormat('yyyy/MM/dd HH:mm');

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

  static const _defaultAndroidGanttColumns = 5;
  static const _defaultAndroidGanttRows = 4;
  static const _androidGanttSizeOptions = <_AndroidGanttSizeOption>[
    _AndroidGanttSizeOption(columns: 5, rows: 4, label: '5 x 4（おすすめ）'),
    _AndroidGanttSizeOption(columns: 4, rows: 4, label: '4 x 4'),
    _AndroidGanttSizeOption(columns: 4, rows: 5, label: '4 x 5'),
    _AndroidGanttSizeOption(columns: 5, rows: 5, label: '5 x 5'),
  ];

  String _ganttPosition = _defaultGanttPosition;
  int _androidGanttColumns = _defaultAndroidGanttColumns;
  int _androidGanttRows = _defaultAndroidGanttRows;
  String? _message;
  bool _messageIsError = true;
  bool _isPlacementModeActive = false;
  bool _isPlacementModeChanging = false;
  bool _isAndroidGanttSizeSaving = false;

  bool get _supportsNativeGantt =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _supportsAndroidHomeWidget =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String get _androidGanttSizeValue =>
      _AndroidGanttSizeOption.valueFor(_androidGanttColumns, _androidGanttRows);

  @override
  void initState() {
    super.initState();
    _loadGanttPosition();
    _loadAndroidGanttWidgetSize();
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

  Future<void> _loadAndroidGanttWidgetSize() async {
    if (!_supportsAndroidHomeWidget) {
      return;
    }

    try {
      final size = await _windowChannel.invokeMapMethod<String, Object?>(
        'getAndroidGanttWidgetSize',
      );
      if (!mounted || size == null) {
        return;
      }

      final columns = size['columns'];
      final rows = size['rows'];
      if (columns is! int || rows is! int) {
        return;
      }

      setState(() {
        _androidGanttColumns = columns;
        _androidGanttRows = rows;
      });
    } on MissingPluginException {
      _setMessage('Android 実行時のみ追加できます');
    } on PlatformException {
      _setMessage('小窓サイズを読み込めませんでした');
    }
  }

  Future<void> _setAndroidGanttWidgetSize(String? value) async {
    final option = _AndroidGanttSizeOption.fromValue(
      _androidGanttSizeOptions,
      value,
    );
    if (option == null) {
      return;
    }

    setState(() {
      _androidGanttColumns = option.columns;
      _androidGanttRows = option.rows;
      _isAndroidGanttSizeSaving = true;
      _message = null;
      _messageIsError = true;
    });

    try {
      await _windowChannel.invokeMethod<Map<Object?, Object?>>(
        'setAndroidGanttWidgetSize',
        {'columns': option.columns, 'rows': option.rows},
      );
      if (!mounted) {
        return;
      }

      _setMessage('小窓サイズを${option.valueLabel}に設定しました', isError: false);
    } on MissingPluginException {
      _setMessage('Android 実行時のみ追加できます');
    } on PlatformException {
      _setMessage('小窓サイズを変更できませんでした');
    } finally {
      if (mounted) {
        setState(() {
          _isAndroidGanttSizeSaving = false;
        });
      }
    }
  }

  Future<void> _requestAndroidGanttWidgetPin() async {
    if (!_supportsAndroidHomeWidget) {
      _setMessage('Android 実行時のみ追加できます');
      return;
    }

    try {
      final status = await _windowChannel.invokeMethod<String>(
        'requestPinAndroidGanttWidget',
      );
      if (!mounted) {
        return;
      }

      _setMessage(_androidGanttPinMessage(status), isError: false);
    } on MissingPluginException {
      _setMessage('Android 実行時のみ追加できます');
    } on PlatformException {
      _setMessage('小窓ガントの追加を開始できませんでした');
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

  Future<void> _openProfileDialog(AuthController auth) {
    return showDialog<void>(
      context: context,
      builder: (_) {
        return _ProfileEditDialog(auth: auth, initialUser: auth.currentUser);
      },
    );
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
          _MicrosoftIntegrationPanel(auth: auth),
          const SizedBox(height: 24),
        ],
        Text('小窓ガント', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        if (_supportsNativeGantt)
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
                          _isPlacementModeActive
                              ? Icons.check
                              : Icons.open_with,
                        ),
                  label: Text(_isPlacementModeActive ? '配置モードを終了' : '配置モードを起動'),
                ),
            ],
          )
        else if (_supportsAndroidHomeWidget)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_androidGanttSizeValue),
                  initialValue: _androidGanttSizeValue,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '表示サイズ',
                  ),
                  items: [
                    for (final option in _androidGanttSizeOptions)
                      DropdownMenuItem<String>(
                        value: option.value,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: _isAndroidGanttSizeSaving
                      ? null
                      : _setAndroidGanttWidgetSize,
                ),
              ),
              FilledButton.icon(
                onPressed: _requestAndroidGanttWidgetPin,
                icon: const Icon(Icons.dashboard_customize),
                label: const Text('ホームに追加'),
              ),
            ],
          )
        else
          Text(
            'この環境では小窓ガントを利用できません',
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.auth, required this.initialUser});

  final AuthController auth;
  final AppUser initialUser;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _userIdController;

  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    _displayNameController = TextEditingController(
      text: widget.initialUser.displayName,
    );
    _userIdController = TextEditingController(text: widget.initialUser.userId);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  void _cancel() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    final displayName = _displayNameController.text.trim();
    final userId = _userIdController.text.trim();

    if (displayName.isEmpty) {
      setState(() {
        _errorText = '表示名を入力してください';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    var shouldResetSaving = true;

    try {
      await widget.auth.updateProfile(userId: userId, displayName: displayName);

      if (!mounted) {
        return;
      }

      shouldResetSaving = false;
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop();
    } on DuplicateUserIdException {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = 'このユーザーIDは既に使われています';
      });
    } on InvalidUserIdException {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = 'ユーザーIDは3-32文字の英数字・._-で入力してください';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = 'プロフィールを更新できませんでした';
      });
    } finally {
      if (shouldResetSaving && mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: const Text('プロフィール編集'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _displayNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '表示名',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userIdController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isSaving) {
                    _save();
                  }
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'ユーザーID',
                  helperText: '3-32文字 / 英数字・._-',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorText!,
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
            onPressed: _isSaving ? null : _cancel,
            child: const Text('キャンセル'),
          ),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _GanttPositionOption {
  const _GanttPositionOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _AndroidGanttSizeOption {
  const _AndroidGanttSizeOption({
    required this.columns,
    required this.rows,
    required this.label,
  });

  final int columns;
  final int rows;
  final String label;

  String get value => valueFor(columns, rows);
  String get valueLabel => '$columns x $rows';

  static String valueFor(int columns, int rows) {
    return '$columns:$rows';
  }

  static _AndroidGanttSizeOption? fromValue(
    List<_AndroidGanttSizeOption> options,
    String? value,
  ) {
    for (final option in options) {
      if (option.value == value) {
        return option;
      }
    }

    return null;
  }
}

String _androidGanttPinMessage(String? status) {
  switch (status) {
    case 'requested':
      return 'ホーム画面への追加を確認してください';
    case 'alreadyAdded':
      return '小窓ガントは既にホーム画面にあります';
    case 'unsupported':
    default:
      return 'ウィジェット一覧から小窓ガントを追加してください';
  }
}

class _MicrosoftIntegrationPanel extends StatefulWidget {
  const _MicrosoftIntegrationPanel({required this.auth});

  final AuthController auth;

  @override
  State<_MicrosoftIntegrationPanel> createState() =>
      _MicrosoftIntegrationPanelState();
}

class _MicrosoftIntegrationPanelState
    extends State<_MicrosoftIntegrationPanel> {
  final _integrationRepository = MicrosoftIntegrationRepository();
  final _projectRepository = ProjectRepository();
  final _plannerRepository = MicrosoftPlannerRepository();
  final _deviceCodeRepository = MicrosoftDeviceCodeRepository();

  bool _isConnecting = false;
  bool _isSyncing = false;
  bool _isSaving = false;
  bool _isDisconnecting = false;
  String? _selectedProjectId;
  bool? _autoImportEnabled;
  String? _localMicrosoftError;

  bool get _isBusy =>
      _isConnecting || _isSyncing || _isSaving || _isDisconnecting;

  bool get _usesMicrosoftDeviceCode {
    return !kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
  }

  bool get _hasBundledMicrosoftClientId {
    return MicrosoftDeviceCodeRepository.defaultClientId.trim().isNotEmpty;
  }

  Future<void> _connect(
    MicrosoftIntegration integration,
    List<Project> projects,
  ) async {
    final registration = await _openMicrosoftRegistrationDialog(
      projects: projects,
      initialProjectId: _effectiveProjectId(integration, projects),
      initialAutoImportEnabled: _effectiveAutoImportEnabled(integration),
      initialClientId: _effectiveMicrosoftClientId(integration),
      showClientIdField:
          _usesMicrosoftDeviceCode && !_hasBundledMicrosoftClientId,
    );

    if (registration == null || !mounted) {
      return;
    }

    final projectId = registration.projectId;
    final autoImportEnabled = registration.autoImportEnabled;
    final clientId =
        registration.clientId ?? _effectiveMicrosoftClientId(integration);

    setState(() {
      _isConnecting = true;
      _selectedProjectId = projectId;
      _autoImportEnabled = autoImportEnabled;
      _localMicrosoftError = null;
    });

    var savedIntegration = false;

    try {
      final authResult = await _authenticateMicrosoftPlannerAccount(
        linkAccount: true,
        clientId: clientId,
      );

      if (authResult == null) {
        return;
      }

      await _integrationRepository.saveLinkedAccount(
        userId: widget.auth.currentUser.id,
        accountEmail: authResult.accountEmail,
        displayName: authResult.displayName,
        tenantId: authResult.tenantId,
        clientId: clientId,
        targetProjectId: projectId,
        autoImportEnabled: autoImportEnabled,
      );
      savedIntegration = true;

      if (!autoImportEnabled) {
        _showSnackBar('Microsoft 組織アカウントを連携しました');
        return;
      }

      final result = await _syncWithAccessToken(
        authResult.accessToken,
        projectId,
      );
      _showSnackBar('${result.syncedTaskCount}件の Teams 課題を同期しました');
    } catch (error) {
      final message = _microsoftErrorMessage(error);
      if (savedIntegration) {
        await _integrationRepository.recordSyncFailure(
          userId: widget.auth.currentUser.id,
          error: error,
        );
      }
      if (mounted) {
        setState(() {
          _localMicrosoftError = message;
        });
      }
      _showSnackBar(message);
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<_MicrosoftRegistrationRequest?> _openMicrosoftRegistrationDialog({
    required List<Project> projects,
    required String? initialProjectId,
    required bool initialAutoImportEnabled,
    required String? initialClientId,
    required bool showClientIdField,
  }) {
    var selectedProjectId = initialProjectId;
    var autoImportEnabled = initialAutoImportEnabled;
    final clientIdController = TextEditingController(text: initialClientId);
    String? errorText;

    return showDialog<_MicrosoftRegistrationRequest>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasProjects = projects.isNotEmpty;

            return AlertDialog(
              title: const Text('Microsoft 組織アカウント登録'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.account_circle_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Microsoft のサインイン画面で組織アカウントを登録します。',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (showClientIdField) ...[
                      TextField(
                        controller: clientIdController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Azure アプリケーション (client) ID',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      key: ValueKey(selectedProjectId),
                      initialValue: selectedProjectId,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: '課題を追加するプロジェクト',
                        prefixIcon: const Icon(Icons.folder_outlined),
                        helperText: hasProjects ? null : '先にプロジェクトを作成してください',
                      ),
                      items: [
                        for (final project in projects)
                          DropdownMenuItem<String>(
                            value: project.id,
                            child: Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: hasProjects
                          ? (projectId) {
                              setDialogState(() {
                                selectedProjectId = projectId;
                              });
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: autoImportEnabled,
                      onChanged: (value) {
                        setDialogState(() {
                          autoImportEnabled = value;
                        });
                      },
                      title: const Text('登録後に自動で課題を追加'),
                      subtitle: const Text('Microsoft Planner の割り当てタスクを同期します'),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('キャンセル'),
                ),
                FilledButton.icon(
                  onPressed: selectedProjectId == null
                      ? null
                      : () {
                          final clientId = clientIdController.text.trim();
                          if (showClientIdField && clientId.isEmpty) {
                            setDialogState(() {
                              errorText =
                                  'Azure アプリケーション (client) ID を入力してください';
                            });
                            return;
                          }

                          Navigator.pop(
                            dialogContext,
                            _MicrosoftRegistrationRequest(
                              projectId: selectedProjectId!,
                              autoImportEnabled: autoImportEnabled,
                              clientId: clientId.isEmpty ? null : clientId,
                            ),
                          );
                        },
                  icon: const Icon(Icons.login),
                  label: const Text('Microsoft で登録'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(clientIdController.dispose);
  }

  Future<_MicrosoftAuthResult?> _authenticateMicrosoftPlannerAccount({
    required bool linkAccount,
    String? clientId,
  }) async {
    if (_usesMicrosoftDeviceCode) {
      return _authenticateMicrosoftWithDeviceCode(clientId);
    }

    final credential = linkAccount
        ? await widget.auth.linkMicrosoftPlannerAccount()
        : await widget.auth.reauthenticateMicrosoftPlannerAccount();
    return _MicrosoftAuthResult.fromFirebaseCredential(credential);
  }

  Future<_MicrosoftAuthResult?> _authenticateMicrosoftWithDeviceCode(
    String? clientId,
  ) async {
    final normalizedClientId = clientId?.trim();
    if (normalizedClientId == null || normalizedClientId.isEmpty) {
      throw StateError('Azure アプリケーション (client) ID を入力してください');
    }

    final token = await showDialog<MicrosoftDeviceCodeToken>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _MicrosoftDeviceCodeDialog(
          repository: _deviceCodeRepository,
          clientId: normalizedClientId,
        );
      },
    );

    if (token == null) {
      return null;
    }

    final profile = await _plannerRepository.fetchCurrentUserProfile(
      token.accessToken,
    );

    return _MicrosoftAuthResult(
      accessToken: token.accessToken,
      accountEmail: profile.accountEmail,
      displayName: profile.displayName,
    );
  }

  Future<void> _saveSettings(
    MicrosoftIntegration integration,
    List<Project> projects,
  ) async {
    final projectId = _effectiveProjectId(integration, projects);

    if (projectId == null) {
      _showSnackBar('同期先プロジェクトを選択してください');
      return;
    }

    setState(() {
      _isSaving = true;
      _localMicrosoftError = null;
    });

    try {
      await _integrationRepository.updateSettings(
        userId: widget.auth.currentUser.id,
        targetProjectId: projectId,
        autoImportEnabled: _effectiveAutoImportEnabled(integration),
        clientId: _usesMicrosoftDeviceCode
            ? _effectiveMicrosoftClientId(integration)
            : null,
      );
      _showSnackBar('Microsoft 連携設定を保存しました');
    } catch (_) {
      _showSnackBar('Microsoft 連携設定を保存できませんでした');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _sync(
    MicrosoftIntegration integration,
    List<Project> projects,
  ) async {
    final projectId = _effectiveProjectId(integration, projects);

    if (!integration.isConnected) {
      _showSnackBar('先に Microsoft 組織アカウントを連携してください');
      return;
    }

    if (projectId == null) {
      _showSnackBar('同期先プロジェクトを選択してください');
      return;
    }

    setState(() {
      _isSyncing = true;
      _localMicrosoftError = null;
    });

    try {
      await _integrationRepository.updateSettings(
        userId: widget.auth.currentUser.id,
        targetProjectId: projectId,
        autoImportEnabled: _effectiveAutoImportEnabled(integration),
        clientId: _usesMicrosoftDeviceCode
            ? _effectiveMicrosoftClientId(integration)
            : null,
      );
      final authResult = await _authenticateMicrosoftPlannerAccount(
        linkAccount: false,
        clientId: _effectiveMicrosoftClientId(integration),
      );

      if (authResult == null) {
        return;
      }

      final result = await _syncWithAccessToken(
        authResult.accessToken,
        projectId,
      );
      _showSnackBar('${result.syncedTaskCount}件の Teams 課題を同期しました');
    } catch (error) {
      final message = _microsoftErrorMessage(error);
      await _integrationRepository.recordSyncFailure(
        userId: widget.auth.currentUser.id,
        error: error,
      );
      if (mounted) {
        setState(() {
          _localMicrosoftError = message;
        });
      }
      _showSnackBar(message);
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<MicrosoftPlannerSyncResult> _syncWithAccessToken(
    String accessToken,
    String targetProjectId,
  ) async {
    if (accessToken.trim().isEmpty) {
      throw StateError('Microsoft Graph のアクセストークンを取得できませんでした');
    }

    final result = await _plannerRepository.syncAssignedTasks(
      accessToken: accessToken,
      targetProjectId: targetProjectId,
      appUserId: widget.auth.currentUser.id,
      assigneeName: widget.auth.currentUser.label,
    );

    await _integrationRepository.recordSyncSuccess(
      userId: widget.auth.currentUser.id,
      syncedTaskCount: result.syncedTaskCount,
    );

    return result;
  }

  Future<void> _disconnect(MicrosoftIntegration integration) async {
    final shouldDisconnect = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Microsoft 連携を解除しますか'),
          content: const Text('連携設定を削除します。取り込み済みのタスクは残ります。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.link_off),
              label: const Text('解除'),
            ),
          ],
        );
      },
    );

    if (shouldDisconnect != true || !mounted) {
      return;
    }

    setState(() {
      _isDisconnecting = true;
      _localMicrosoftError = null;
    });

    try {
      await widget.auth.unlinkMicrosoftAccount();
      await _integrationRepository.disconnect(integration.userId);
      setState(() {
        _selectedProjectId = null;
        _autoImportEnabled = null;
      });
      _showSnackBar('Microsoft 連携を解除しました');
    } catch (error) {
      final message = _microsoftErrorMessage(error);
      if (mounted) {
        setState(() {
          _localMicrosoftError = message;
        });
      }
      _showSnackBar(message);
    } finally {
      if (mounted) {
        setState(() {
          _isDisconnecting = false;
        });
      }
    }
  }

  String? _effectiveProjectId(
    MicrosoftIntegration integration,
    List<Project> projects,
  ) {
    final projectIds = projects.map((project) => project.id).toSet();

    for (final candidate in [_selectedProjectId, integration.targetProjectId]) {
      if (candidate != null && projectIds.contains(candidate)) {
        return candidate;
      }
    }

    if (projects.length == 1) {
      return projects.first.id;
    }

    return null;
  }

  bool _effectiveAutoImportEnabled(MicrosoftIntegration integration) {
    return _autoImportEnabled ?? integration.autoImportEnabled;
  }

  String? _effectiveMicrosoftClientId(MicrosoftIntegration integration) {
    final defaultClientId = MicrosoftDeviceCodeRepository.defaultClientId
        .trim();
    if (defaultClientId.isNotEmpty) {
      return defaultClientId;
    }

    final integrationClientId = integration.clientId?.trim();
    if (integrationClientId != null && integrationClientId.isNotEmpty) {
      return integrationClientId;
    }

    return null;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.auth.currentUser;

    return StreamBuilder<MicrosoftIntegration>(
      stream: _integrationRepository.watchIntegration(currentUser.id),
      builder: (context, integrationSnapshot) {
        final integration =
            integrationSnapshot.data ??
            MicrosoftIntegration.disconnected(currentUser.id);

        return StreamBuilder<List<Project>>(
          stream: _projectRepository.watchProjects(memberId: currentUser.id),
          builder: (context, projectSnapshot) {
            final projects = projectSnapshot.data ?? const <Project>[];
            final selectedProjectId = _effectiveProjectId(
              integration,
              projects,
            );
            final autoImportEnabled = _effectiveAutoImportEnabled(integration);
            final isLoadingProjects =
                projectSnapshot.connectionState == ConnectionState.waiting &&
                !projectSnapshot.hasData;

            return _MicrosoftIntegrationContent(
              integration: integration,
              projects: projects,
              selectedProjectId: selectedProjectId,
              autoImportEnabled: autoImportEnabled,
              isLoadingIntegration:
                  integrationSnapshot.connectionState ==
                      ConnectionState.waiting &&
                  !integrationSnapshot.hasData,
              isLoadingProjects: isLoadingProjects,
              isConnecting: _isConnecting,
              isSyncing: _isSyncing,
              isSaving: _isSaving,
              isDisconnecting: _isDisconnecting,
              errorText: _localMicrosoftError ?? integration.lastSyncError,
              isBusy: _isBusy,
              onProjectChanged: (projectId) {
                setState(() {
                  _selectedProjectId = projectId;
                  _localMicrosoftError = null;
                });
              },
              onAutoImportChanged: (value) {
                setState(() {
                  _autoImportEnabled = value;
                  _localMicrosoftError = null;
                });
              },
              onConnect: () => _connect(integration, projects),
              onSave: integration.isConnected
                  ? () => _saveSettings(integration, projects)
                  : null,
              onSync: integration.isConnected
                  ? () => _sync(integration, projects)
                  : null,
              onDisconnect: integration.isConnected
                  ? () => _disconnect(integration)
                  : null,
            );
          },
        );
      },
    );
  }
}

class _MicrosoftRegistrationRequest {
  const _MicrosoftRegistrationRequest({
    required this.projectId,
    required this.autoImportEnabled,
    this.clientId,
  });

  final String projectId;
  final bool autoImportEnabled;
  final String? clientId;
}

class _MicrosoftAuthResult {
  const _MicrosoftAuthResult({
    required this.accessToken,
    this.accountEmail,
    this.displayName,
    this.tenantId,
  });

  final String accessToken;
  final String? accountEmail;
  final String? displayName;
  final String? tenantId;

  factory _MicrosoftAuthResult.fromFirebaseCredential(
    firebase_auth.UserCredential credential,
  ) {
    final accessToken = credential.credential?.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw StateError('Microsoft Graph のアクセストークンを取得できませんでした');
    }

    final profile = credential.additionalUserInfo?.profile;

    return _MicrosoftAuthResult(
      accessToken: accessToken,
      accountEmail:
          _readProfileValue(profile, const [
            'mail',
            'userPrincipalName',
            'email',
            'preferred_username',
          ]) ??
          credential.user?.email,
      displayName:
          _readProfileValue(profile, const ['displayName', 'name']) ??
          credential.user?.displayName,
      tenantId: _readProfileValue(profile, const ['tid', 'tenantId']),
    );
  }
}

class _MicrosoftDeviceCodeDialog extends StatefulWidget {
  const _MicrosoftDeviceCodeDialog({
    required this.repository,
    required this.clientId,
  });

  final MicrosoftDeviceCodeRepository repository;
  final String clientId;

  @override
  State<_MicrosoftDeviceCodeDialog> createState() =>
      _MicrosoftDeviceCodeDialogState();
}

class _MicrosoftDeviceCodeDialogState
    extends State<_MicrosoftDeviceCodeDialog> {
  MicrosoftDeviceCodeSession? _session;
  String? _errorText;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _startAuthentication();
  }

  @override
  void dispose() {
    _isCancelled = true;
    super.dispose();
  }

  Future<void> _startAuthentication() async {
    try {
      final session = await widget.repository.startDeviceCode(
        clientId: widget.clientId,
      );

      if (!mounted || _isCancelled) {
        return;
      }

      setState(() {
        _session = session;
        _errorText = null;
      });

      await _openVerificationUri(session.verificationUri, showError: false);

      final token = await widget.repository.pollToken(
        clientId: widget.clientId,
        session: session,
        isCancelled: () => _isCancelled,
      );

      if (!mounted || _isCancelled) {
        return;
      }

      Navigator.pop(context, token);
    } on MicrosoftDeviceCodeCancelledException {
      return;
    } catch (error) {
      if (!mounted || _isCancelled) {
        return;
      }

      setState(() {
        _errorText = _microsoftErrorMessage(error);
      });
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$labelをコピーしました')));
  }

  Future<void> _openVerificationUri(
    String value, {
    bool showError = true,
  }) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      if (showError && mounted) {
        setState(() {
          _errorText = 'Microsoft 認証ページの URL が正しくありません';
        });
      }
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && showError && mounted) {
        setState(() {
          _errorText = 'ブラウザを開けませんでした。URLコピーで開いてください。';
        });
      }
    } catch (_) {
      if (showError && mounted) {
        setState(() {
          _errorText = 'ブラウザを開けませんでした。URLコピーで開いてください。';
        });
      }
    }
  }

  void _cancel() {
    _isCancelled = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Microsoft 組織アカウント認証'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session == null && _errorText == null)
              const Center(child: CircularProgressIndicator())
            else if (session != null) ...[
              const Text('ブラウザで Microsoft にサインインし、下のコードを入力してください。'),
              const SizedBox(height: 16),
              _AccountValueRow(
                icon: Icons.language,
                label: 'URL',
                value: session.verificationUri,
              ),
              const SizedBox(height: 8),
              _AccountValueRow(
                icon: Icons.pin_outlined,
                label: 'コード',
                value: session.userCode,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                color: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ],
            if (_errorText != null) ...[
              if (session != null) const SizedBox(height: 12),
              Text(_errorText!, style: TextStyle(color: colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (session != null) ...[
          TextButton.icon(
            onPressed: () => _openVerificationUri(session.verificationUri),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('ブラウザで開く'),
          ),
          TextButton.icon(
            onPressed: () => _copy(session.verificationUri, 'URL'),
            icon: const Icon(Icons.copy),
            label: const Text('URLコピー'),
          ),
          TextButton.icon(
            onPressed: () => _copy(session.userCode, 'コード'),
            icon: const Icon(Icons.copy),
            label: const Text('コードコピー'),
          ),
        ],
        TextButton(onPressed: _cancel, child: const Text('キャンセル')),
      ],
    );
  }
}

class _MicrosoftIntegrationContent extends StatelessWidget {
  const _MicrosoftIntegrationContent({
    required this.integration,
    required this.projects,
    required this.selectedProjectId,
    required this.autoImportEnabled,
    required this.isLoadingIntegration,
    required this.isLoadingProjects,
    required this.isConnecting,
    required this.isSyncing,
    required this.isSaving,
    required this.isDisconnecting,
    required this.errorText,
    required this.isBusy,
    required this.onProjectChanged,
    required this.onAutoImportChanged,
    required this.onConnect,
    required this.onSave,
    required this.onSync,
    required this.onDisconnect,
  });

  final MicrosoftIntegration integration;
  final List<Project> projects;
  final String? selectedProjectId;
  final bool autoImportEnabled;
  final bool isLoadingIntegration;
  final bool isLoadingProjects;
  final bool isConnecting;
  final bool isSyncing;
  final bool isSaving;
  final bool isDisconnecting;
  final String? errorText;
  final bool isBusy;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<bool> onAutoImportChanged;
  final VoidCallback onConnect;
  final VoidCallback? onSave;
  final VoidCallback? onSync;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canChooseProject = projects.isNotEmpty && !isBusy;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.groups_2_outlined, color: colorScheme.primary),
              Text('Microsoft Teams / Planner', style: textTheme.titleMedium),
              _IntegrationStatusChip(isConnected: integration.isConnected),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Teams に紐づく Planner の割り当てタスクを、選択したプロジェクトへ取り込みます。',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(selectedProjectId),
            initialValue: selectedProjectId,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: '同期先プロジェクト',
              prefixIcon: const Icon(Icons.folder_outlined),
              helperText: projects.isEmpty && !isLoadingProjects
                  ? '先にプロジェクトを作成してください'
                  : null,
            ),
            items: [
              for (final project in projects)
                DropdownMenuItem<String>(
                  value: project.id,
                  child: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: canChooseProject ? onProjectChanged : null,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: autoImportEnabled,
            onChanged: isBusy ? null : onAutoImportChanged,
            title: const Text('連携後に自動で課題を追加'),
            subtitle: const Text('手動同期もいつでも実行できます'),
          ),
          if (integration.isConnected) ...[
            const Divider(height: 28),
            _MicrosoftAccountSummary(integration: integration),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              errorText!,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!integration.isConnected)
                FilledButton.icon(
                  onPressed: isBusy || isLoadingIntegration ? null : onConnect,
                  icon: isConnecting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: const Text('組織アカウントを登録'),
                )
              else ...[
                FilledButton.tonalIcon(
                  onPressed: isBusy ? null : onSave,
                  icon: isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('設定を保存'),
                ),
                FilledButton.icon(
                  onPressed: isBusy ? null : onSync,
                  icon: isSyncing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('今すぐ同期'),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onDisconnect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  icon: isDisconnecting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_off),
                  label: const Text('連携解除'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _IntegrationStatusChip extends StatelessWidget {
  const _IntegrationStatusChip({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isConnected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = isConnected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Chip(
      avatar: Icon(
        isConnected ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 16,
        color: foregroundColor,
      ),
      label: Text(isConnected ? '連携済み' : '未連携'),
      backgroundColor: backgroundColor,
      labelStyle: TextStyle(color: foregroundColor),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MicrosoftAccountSummary extends StatelessWidget {
  const _MicrosoftAccountSummary({required this.integration});

  final MicrosoftIntegration integration;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (integration.displayName != null)
          _AccountValueRow(
            icon: Icons.badge_outlined,
            label: '表示名',
            value: integration.displayName!,
          ),
        if (integration.displayName != null) const SizedBox(height: 8),
        if (integration.accountEmail != null)
          _AccountValueRow(
            icon: Icons.mail_outline,
            label: 'アカウント',
            value: integration.accountEmail!,
          ),
        if (integration.accountEmail != null) const SizedBox(height: 8),
        if (integration.tenantId != null)
          _AccountValueRow(
            icon: Icons.apartment,
            label: 'テナント',
            value: integration.tenantId!,
          ),
        if (integration.tenantId != null) const SizedBox(height: 8),
        _AccountValueRow(
          icon: Icons.schedule,
          label: '最終同期',
          value: integration.lastSyncedAt == null
              ? '未同期'
              : '${_settingsDateTimeFormat.format(integration.lastSyncedAt!)} / ${integration.lastSyncedTaskCount}件',
        ),
      ],
    );
  }
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

String? _readProfileValue(
  Map<String, dynamic>? profile,
  Iterable<String> keys,
) {
  if (profile == null) {
    return null;
  }

  for (final key in keys) {
    final value = profile[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }

  return null;
}

String _microsoftErrorMessage(Object error) {
  if (error is MicrosoftGraphException) {
    if (error.statusCode == 403) {
      return 'Microsoft Planner の読み取り権限がありません。組織管理者の承認が必要な可能性があります。';
    }

    return error.message;
  }

  if (error is MicrosoftDeviceCodeException) {
    switch (error.code) {
      case 'authorization_declined':
        return 'Microsoft 認証が拒否されました';
      case 'expired_token':
        return 'Microsoft 認証コードの有効期限が切れました';
      case 'invalid_client':
      case 'unauthorized_client':
        return 'Azure アプリケーション (client) ID が正しくないか、公開クライアント フローが許可されていません';
      case 'invalid_scope':
        return 'Microsoft Graph の Tasks.Read 権限を要求できませんでした';
    }

    return 'Microsoft 認証に失敗しました: ${error.code} / ${error.message}';
  }

  if (error is MicrosoftDeviceCodeCancelledException) {
    return 'Microsoft 連携をキャンセルしました';
  }

  if (error is firebase_auth.FirebaseAuthException) {
    switch (error.code) {
      case 'operation-not-allowed':
        return 'Firebase Auth で Microsoft プロバイダが有効化されていません';
      case 'operation-not-supported-in-this-environment':
      case 'unimplemented':
        return 'この実行環境では Microsoft OAuth 連携がサポートされていません';
      case 'unauthorized-domain':
        return 'Firebase Auth の承認済みドメインに現在のドメインが登録されていません';
      case 'invalid-oauth-provider':
      case 'invalid-oauth-client-id':
      case 'app-not-authorized':
        return 'Microsoft OAuth の設定が正しくありません。Firebase と Azure の設定を確認してください';
      case 'network-request-failed':
        return 'ネットワーク接続に失敗しました';
      case 'popup-blocked':
        return 'Microsoft サインイン画面がブロックされました';
      case 'account-exists-with-different-credential':
        return 'この Microsoft アカウントは別のログイン方法で既に使われています';
      case 'credential-already-in-use':
        return 'この Microsoft アカウントは別の TaskMan ユーザーに連携済みです';
      case 'popup-closed-by-user':
      case 'web-context-canceled':
      case 'web-context-cancelled':
      case 'canceled':
        return 'Microsoft 連携をキャンセルしました';
      case 'requires-recent-login':
        return 'もう一度サインインしてから連携解除してください';
    }

    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return 'Microsoft 連携に失敗しました: ${error.code} / $message';
    }

    return 'Microsoft 連携に失敗しました: ${error.code}';
  }

  if (error is PlatformException) {
    final message = error.message?.trim();
    return message == null || message.isEmpty
        ? 'Microsoft 連携に失敗しました: ${error.code}'
        : 'Microsoft 連携に失敗しました: ${error.code} / $message';
  }

  if (error is UnsupportedError || error is UnimplementedError) {
    return 'この実行環境では Microsoft OAuth 連携がサポートされていません';
  }

  if (error is StateError) {
    return error.message;
  }

  return 'Microsoft 連携処理に失敗しました';
}
