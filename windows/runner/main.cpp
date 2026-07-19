#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const char kDesktopWidgetArgument[] = "--desktop-widget";

bool HasDesktopWidgetArgument(const std::vector<std::string>& arguments) {
  return std::find(arguments.begin(), arguments.end(), kDesktopWidgetArgument) !=
         arguments.end();
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject main_project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool is_desktop_widget =
      HasDesktopWidgetArgument(command_line_arguments);

  main_project.set_dart_entrypoint_arguments(command_line_arguments);
  if (is_desktop_widget) {
    main_project.set_dart_entrypoint("desktopWidgetMain");
  }

  FlutterWindow main_window(main_project);
  if (is_desktop_widget) {
    main_window.SetDesktopWidgetMode(true);
  }

  Win32Window::Point main_origin(is_desktop_widget ? 24 : 10,
                                 is_desktop_widget ? 24 : 10);
  Win32Window::Size main_size(is_desktop_widget ? 560 : 1280,
                              is_desktop_widget ? 360 : 720);
  if (!main_window.Create(is_desktop_widget ? L"taskman gantt" : L"taskman",
                          main_origin, main_size)) {
    return EXIT_FAILURE;
  }
  main_window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
