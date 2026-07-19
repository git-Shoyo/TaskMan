import 'dart:io';

class FileEdit {
  const FileEdit(this.path, this.oldText, this.newText);

  final String path;
  final String oldText;
  final String newText;
}

String adaptNewlines(String value, String newline) {
  return value.replaceAll('\r\n', '\n').replaceAll('\n', newline);
}

int countOccurrences(String source, String pattern) {
  if (pattern.isEmpty) {
    return 0;
  }

  var count = 0;
  var index = 0;
  while (true) {
    index = source.indexOf(pattern, index);
    if (index < 0) {
      return count;
    }
    count++;
    index += pattern.length;
  }
}

void main() {
  final edits = <FileEdit>[
    const FileEdit(
      'lib/widgets/native_gantt_bridge.dart',
      '''
  @override
  void dispose() {
    unawaited(_projectsSubscription?.cancel());
    unawaited(_tasksSubscription?.cancel());
    super.dispose();
  }
''',
      '''
  @override
  void dispose() {
    unawaited(_setNativeGanttVisible(false));
    unawaited(_projectsSubscription?.cancel());
    unawaited(_tasksSubscription?.cancel());
    super.dispose();
  }
''',
    ),
    const FileEdit(
      'lib/widgets/native_gantt_bridge.dart',
      '''
    final nextMemberId =
        auth != null && auth.isSignedIn && !auth.needsEmailVerification
        ? auth.currentUser.id
        : null;

    if (_memberId == nextMemberId) {
''',
      '''
    final nextMemberId =
        auth != null && auth.isSignedIn && !auth.needsEmailVerification
        ? auth.currentUser.id
        : null;

    unawaited(_setNativeGanttVisible(nextMemberId != null));

    if (_memberId == nextMemberId) {
''',
    ),
    const FileEdit(
      'lib/widgets/native_gantt_bridge.dart',
      '''
  Future<void> _sendTasks(List<Task> tasks) async {
''',
      '''
  Future<void> _setNativeGanttVisible(bool visible) async {
    try {
      await _windowChannel.invokeMethod<void>(
        'setNativeGanttVisible',
        visible,
      );
    } on MissingPluginException {
      // The native gantt is optional on unsupported platforms and in tests.
    } on PlatformException {
      // Visibility failures must not interrupt the main application.
    }
  }

  Future<void> _sendTasks(List<Task> tasks) async {
''',
    ),
    const FileEdit(
      'windows/runner/flutter_window.cpp',
      '''
        if (call.method_name() == "updateNativeGanttTasks") {
          UpdateNativeGanttTasks(ParseNativeGanttTasks(call.arguments()));
          result->Success();
          return;
        }

        if (call.method_name() == "getNativeGanttPosition") {
''',
      '''
        if (call.method_name() == "updateNativeGanttTasks") {
          UpdateNativeGanttTasks(ParseNativeGanttTasks(call.arguments()));
          result->Success();
          return;
        }

        if (call.method_name() == "setNativeGanttVisible") {
          const auto* arguments = call.arguments();
          if (arguments != nullptr) {
            if (const auto* visible = std::get_if<bool>(arguments)) {
              if (*visible) {
                ShowNativeGanttWindow();
              } else {
                HideNativeGanttWindow();
              }
            }
          }
          result->Success();
          return;
        }

        if (call.method_name() == "getNativeGanttPosition") {
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.h',
      '''
  bool quit_on_close_ = false;
  bool desktop_widget_mode_ = false;
  NativeGanttWindow native_gantt_window_;
''',
      '''
  bool quit_on_close_ = false;
  bool desktop_widget_mode_ = false;
  bool native_gantt_visible_ = false;
  NativeGanttWindow native_gantt_window_;
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
  native_gantt_window_.Show();

  return did_show;
''',
      '''
  if (native_gantt_visible_) {
    native_gantt_window_.Show();
  }

  return did_show;
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
  native_gantt_window_.SetPlacementMode(false);
  native_gantt_window_.Show();
  ShowWindow(window_handle_, SW_HIDE);
''',
      '''
  native_gantt_window_.SetPlacementMode(false);
  if (native_gantt_visible_) {
    native_gantt_window_.Show();
  }
  ShowWindow(window_handle_, SW_HIDE);
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
void Win32Window::ShowNativeGanttWindow() {
  native_gantt_window_.Show();
}

void Win32Window::HideNativeGanttWindow() {
  native_gantt_window_.Hide();
}
''',
      '''
void Win32Window::ShowNativeGanttWindow() {
  native_gantt_visible_ = true;
  native_gantt_window_.Show();
}

void Win32Window::HideNativeGanttWindow() {
  native_gantt_visible_ = false;
  native_gantt_window_.Hide();
}
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
  if (!SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    ShowWindow(window_handle_, SW_SHOWNORMAL);
    native_gantt_window_.Show();
    return;
  }
''',
      '''
  if (!SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    ShowWindow(window_handle_, SW_SHOWNORMAL);
    if (native_gantt_visible_) {
      native_gantt_window_.Show();
    }
    return;
  }
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
  BringWindowToTop(window_handle_);
  SetForegroundWindow(window_handle_);
  UpdateWindow(window_handle_);
  native_gantt_window_.Show();
}
''',
      '''
  BringWindowToTop(window_handle_);
  SetForegroundWindow(window_handle_);
  UpdateWindow(window_handle_);
  if (native_gantt_visible_) {
    native_gantt_window_.Show();
  }
}
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
    case WM_CLOSE:
      if (desktop_widget_mode_) {
        native_gantt_window_.Show();
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
''',
      '''
    case WM_CLOSE:
      if (desktop_widget_mode_) {
        if (native_gantt_visible_) {
          native_gantt_window_.Show();
        }
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
        if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
          native_gantt_window_.Show();
        } else if (lparam == WM_RBUTTONUP) {
''',
      '''
        if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
          if (native_gantt_visible_) {
            native_gantt_window_.Show();
          }
        } else if (lparam == WM_RBUTTONUP) {
''',
    ),
    const FileEdit(
      'windows/runner/win32_window.cpp',
      '''
          if (command == kTrayMenuShow) {
            native_gantt_window_.Show();
          } else if (command == kTrayMenuMainWindow) {
''',
      '''
          if (command == kTrayMenuShow) {
            if (native_gantt_visible_) {
              native_gantt_window_.Show();
            }
          } else if (command == kTrayMenuMainWindow) {
''',
    ),
  ];

  final fileContents = <String, String>{};
  final changedFiles = <String>{};
  final alreadyApplied = <String>[];

  try {
    for (final edit in edits) {
      final file = File(edit.path);
      if (!file.existsSync()) {
        throw StateError('ファイルが見つかりません: ${edit.path}');
      }

      var content = fileContents[edit.path] ?? file.readAsStringSync();
      final newline = content.contains('\r\n') ? '\r\n' : '\n';
      final oldText = adaptNewlines(edit.oldText, newline);
      final newText = adaptNewlines(edit.newText, newline);

      final oldCount = countOccurrences(content, oldText);
      final newCount = countOccurrences(content, newText);

      if (oldCount == 1) {
        content = content.replaceFirst(oldText, newText);
        fileContents[edit.path] = content;
        changedFiles.add(edit.path);
        continue;
      }

      if (oldCount == 0 && newCount == 1) {
        alreadyApplied.add(edit.path);
        fileContents[edit.path] = content;
        continue;
      }

      throw StateError(
        '${edit.path} の置換対象が一意に見つかりません '
        '(変更前: $oldCount 件 / 変更後: $newCount 件)',
      );
    }
  } catch (error) {
    stderr.writeln('適用を中止しました。ファイルは変更していません。');
    stderr.writeln(error);
    exitCode = 1;
    return;
  }

  for (final entry in fileContents.entries) {
    if (!changedFiles.contains(entry.key)) {
      continue;
    }
    File(entry.key).writeAsStringSync(entry.value);
  }

  if (changedFiles.isEmpty) {
    stdout.writeln('変更はすでに適用済みです。');
    return;
  }

  stdout.writeln('次のファイルを更新しました:');
  for (final path in changedFiles) {
    stdout.writeln('  - $path');
  }

  if (alreadyApplied.isNotEmpty) {
    stdout.writeln('一部の変更はすでに適用済みでした。');
  }

  stdout.writeln('');
  stdout.writeln('続けて次を実行してください:');
  stdout.writeln('  dart format lib/widgets/native_gantt_bridge.dart');
  stdout.writeln('  flutter analyze');
  stdout.writeln('  flutter run -d windows');
}
