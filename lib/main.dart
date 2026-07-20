import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'layouts/responsive_layout.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/email_verification_screen.dart';
import 'screens/auth/get_started_screen.dart';
import 'screens/desktop_gantt_widget_screen.dart';
import 'screens/task_detail_screen.dart';
import 'services/task_notification_service.dart';
import 'systems/auth_controller.dart';
import 'systems/auth_scope.dart';
import 'widgets/native_gantt_bridge.dart';
import 'widgets/task_reminder_overlay.dart';

const desktopWidgetArgument = '--desktop-widget';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final showDesktopWidget = args.contains(desktopWidgetArgument);

  if (showDesktopWidget) {
    runApp(
      TaskMan(
        showDesktopWidget: true,
        firebaseInitialization: Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ),
      ),
    );
    return;
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await TaskNotificationService.instance.initialize();

  runApp(const TaskMan(showDesktopWidget: false));
}

@pragma('vm:entry-point')
Future<void> desktopWidgetMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    TaskMan(
      showDesktopWidget: true,
      firebaseInitialization: Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
    ),
  );
}

class TaskMan extends StatefulWidget {
  const TaskMan({
    super.key,
    required this.showDesktopWidget,
    this.firebaseInitialization,
  });

  final bool showDesktopWidget;
  final Future<FirebaseApp>? firebaseInitialization;

  @override
  State<TaskMan> createState() => _TaskManState();
}

class _TaskManState extends State<TaskMan> {
  static const _windowChannel = MethodChannel('taskman/window');

  final _navigatorKey = GlobalKey<NavigatorState>();
  late bool _showDesktopWidget;
  AuthController? _authController;

  @override
  void initState() {
    super.initState();
    _showDesktopWidget = widget.showDesktopWidget;
    if (!_showDesktopWidget) {
      _ensureAuthController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        TaskNotificationService.instance.setTaskTapHandler(
          _openTaskDetailFromNotification,
        );
      });
    }
    _windowChannel.setMethodCallHandler(_handleWindowMethodCall);
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    TaskNotificationService.instance.setTaskTapHandler(null);
    _authController?.dispose();
    super.dispose();
  }

  AuthController _ensureAuthController() {
    return _authController ??= AuthController();
  }

  Future<void> _handleWindowMethodCall(MethodCall call) async {
    if (call.method == 'showDesktopWidget') {
      if (!mounted) {
        return;
      }
      setState(() {
        _showDesktopWidget = true;
      });
    } else if (call.method == 'showMainWindow') {
      if (!mounted) {
        return;
      }
      _ensureAuthController();
      setState(() {
        _showDesktopWidget = false;
      });
    } else if (call.method == 'openNativeGanttTask') {
      final taskId = call.arguments as String?;
      if (taskId == null || taskId.isEmpty || !mounted) {
        return;
      }

      _ensureAuthController();
      if (_showDesktopWidget) {
        setState(() {
          _showDesktopWidget = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openTaskDetailFromNativeGantt(taskId);
        });
        return;
      }

      _openTaskDetailFromNativeGantt(taskId);
    }
  }

  void _openTaskDetailFromNativeGantt(String taskId) {
    if (!mounted) {
      return;
    }

    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (context) => TaskDetailScreen(taskId: taskId)),
    );
  }

  void _openTaskDetailFromNotification(String taskId) {
    if (taskId.trim().isEmpty || !mounted) {
      return;
    }

    _ensureAuthController();
    if (_showDesktopWidget) {
      setState(() {
        _showDesktopWidget = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openTaskDetailFromNativeGantt(taskId);
      });
      return;
    }

    _openTaskDetailFromNativeGantt(taskId);
  }

  @override
  Widget build(BuildContext context) {
    final home = _showDesktopWidget
        ? _DesktopWidgetBootstrap(
            firebaseInitialization: widget.firebaseInitialization,
          )
        : _MainWindowAuthGate(
            authController: _ensureAuthController(),
            child: const NativeGanttBridge(
              child: TaskReminderOverlay(child: ResponsiveLayout()),
            ),
          );
    final app = MaterialApp(
      key: ValueKey(_showDesktopWidget ? 'desktop-widget' : 'main-window'),
      title: 'TaskMan',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: home,
    );

    if (_showDesktopWidget) {
      return app;
    }

    return AuthScope(controller: _ensureAuthController(), child: app);
  }
}

class _MainWindowAuthGate extends StatefulWidget {
  const _MainWindowAuthGate({
    required this.authController,
    required this.child,
  });

  final AuthController authController;
  final Widget child;

  @override
  State<_MainWindowAuthGate> createState() => _MainWindowAuthGateState();
}

class _MainWindowAuthGateState extends State<_MainWindowAuthGate> {
  AuthScreenMode? _authMode;

  void _openAuthScreen(AuthScreenMode mode) {
    setState(() {
      _authMode = mode;
    });
  }

  void _closeAuthScreen() {
    setState(() {
      _authMode = null;
    });
  }

  void _clearAuthModeAfterSignIn() {
    if (_authMode == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.authController.isSignedIn) {
        return;
      }

      setState(() {
        _authMode = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        if (!widget.authController.isReady ||
            widget.authController.isLoadingProfile) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!widget.authController.isSignedIn) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _authMode != null
                ? AuthScreen(
                    key: ValueKey('auth-${_authMode!.name}'),
                    initialMode: _authMode!,
                    onBack: _closeAuthScreen,
                  )
                : GetStartedScreen(
                    key: const ValueKey('get-started-screen'),
                    onGetStarted: () => _openAuthScreen(AuthScreenMode.signUp),
                    onSignIn: () => _openAuthScreen(AuthScreenMode.signIn),
                  ),
          );
        }

        _clearAuthModeAfterSignIn();

        if (widget.authController.needsEmailVerification) {
          return const EmailVerificationScreen();
        }

        return widget.child;
      },
    );
  }
}

class _DesktopWidgetBootstrap extends StatelessWidget {
  const _DesktopWidgetBootstrap({required this.firebaseInitialization});

  final Future<FirebaseApp>? firebaseInitialization;

  @override
  Widget build(BuildContext context) {
    if (firebaseInitialization == null) {
      return const _DesktopWidgetAuthBootstrap();
    }

    return FutureBuilder<FirebaseApp>(
      future: firebaseInitialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text('読み込みに失敗しました')));
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return const _DesktopWidgetAuthBootstrap();
      },
    );
  }
}

class _DesktopWidgetAuthBootstrap extends StatefulWidget {
  const _DesktopWidgetAuthBootstrap();

  @override
  State<_DesktopWidgetAuthBootstrap> createState() =>
      _DesktopWidgetAuthBootstrapState();
}

class _DesktopWidgetAuthBootstrapState
    extends State<_DesktopWidgetAuthBootstrap> {
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = AuthController();
  }

  @override
  void dispose() {
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      controller: _authController,
      child: AnimatedBuilder(
        animation: _authController,
        builder: (context, _) {
          if (!_authController.isReady || _authController.isLoadingProfile) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return const DesktopGanttWidgetScreen();
        },
      ),
    );
  }
}
