#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayWindowMessage = WM_APP + 1;
constexpr UINT kTrayMenuShow = 1001;
constexpr UINT kTrayMenuMainWindow = 1003;
constexpr UINT kTrayMenuExit = 1004;
constexpr int kDebugVisibleWidgetOffset = 80;

const UINT kTaskbarCreatedMessage = RegisterWindowMessage(L"TaskbarCreated");

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

void ConfigureDesktopWidgetWindow(HWND window,
                                  const Win32Window::Size& size,
                                  double scale_factor) {
  RECT work_area;
  if (!SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    return;
  }

  const int width = Scale(size.width, scale_factor);
  const int height = Scale(size.height, scale_factor);
  const int offset = Scale(kDebugVisibleWidgetOffset, scale_factor);
  const int x = work_area.left + offset;
  const int y = work_area.top + offset;

  SetWindowPos(window, HWND_NOTOPMOST, x, y, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void AddTrayIcon(HWND window) {
  NOTIFYICONDATA notify_icon_data{};
  notify_icon_data.cbSize = sizeof(notify_icon_data);
  notify_icon_data.hWnd = window;
  notify_icon_data.uID = kTrayIconId;
  notify_icon_data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  notify_icon_data.uCallbackMessage = kTrayWindowMessage;
  notify_icon_data.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(notify_icon_data.szTip, L"TaskMan resident gantt");

  Shell_NotifyIcon(NIM_DELETE, &notify_icon_data);
  Shell_NotifyIcon(NIM_ADD, &notify_icon_data);
}

void RemoveTrayIcon(HWND window) {
  NOTIFYICONDATA notify_icon_data{};
  notify_icon_data.cbSize = sizeof(notify_icon_data);
  notify_icon_data.hWnd = window;
  notify_icon_data.uID = kTrayIconId;

  Shell_NotifyIcon(NIM_DELETE, &notify_icon_data);
}

void ShowDesktopWidgetWindow(HWND window) {
  ShowWindow(window, SW_SHOWNORMAL);
  SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW |
                   SWP_NOOWNERZORDER);
  BringWindowToTop(window);
  SetForegroundWindow(window);
  UpdateWindow(window);
  SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW |
                   SWP_NOOWNERZORDER);
}

void ExitDesktopWidget(HWND window) {
  RemoveTrayIcon(window);
  DestroyWindow(window);
}

UINT ShowTrayMenu(HWND window,
                  bool gantt_enabled,
                  bool gantt_visible) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return 0;
  }

  const UINT gantt_menu_flags =
      gantt_enabled ? MF_STRING : (MF_STRING | MF_GRAYED);
  AppendMenu(menu, gantt_menu_flags, kTrayMenuShow,
             gantt_visible ? L"Hide Gantt" : L"Show Gantt");
  AppendMenu(menu, MF_STRING, kTrayMenuMainWindow, L"Main Window");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayMenuExit, L"Exit");

  POINT cursor_position;
  GetCursorPos(&cursor_position);
  SetForegroundWindow(window);

  const UINT command =
      TrackPopupMenu(menu,
                     TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                     cursor_position.x, cursor_position.y, 0, window, nullptr);
  DestroyMenu(menu);

  return command;
}

NativeGanttPosition NativeGanttPositionFromString(
    const std::string& position) {
  if (position == "topRight") {
    return NativeGanttPosition::TopRight;
  }
  if (position == "bottomLeft") {
    return NativeGanttPosition::BottomLeft;
  }
  if (position == "bottomRight") {
    return NativeGanttPosition::BottomRight;
  }
  if (position == "custom") {
    return NativeGanttPosition::Custom;
  }
  return NativeGanttPosition::TopLeft;
}

std::string NativeGanttPositionToString(NativeGanttPosition position) {
  switch (position) {
    case NativeGanttPosition::TopRight:
      return "topRight";
    case NativeGanttPosition::BottomLeft:
      return "bottomLeft";
    case NativeGanttPosition::BottomRight:
      return "bottomRight";
    case NativeGanttPosition::Custom:
      return "custom";
    case NativeGanttPosition::TopLeft:
    default:
      return "topLeft";
  }
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  const DWORD window_style = WS_OVERLAPPEDWINDOW;
  const DWORD window_ex_style = 0;

  HWND window = CreateWindowEx(
      window_ex_style, window_class, title.c_str(), window_style,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);
  native_gantt_window_.SetOwner(window);

  if (desktop_widget_mode_) {
    AddTrayIcon(window);
  }

  return OnCreate();
}

bool Win32Window::Show() {
  const bool did_show = ShowWindow(window_handle_, SW_SHOWNORMAL);

  if (desktop_widget_mode_) {
    ShowDesktopWidgetWindow(window_handle_);
  }

  if (native_gantt_enabled_ && native_gantt_visible_) {
    native_gantt_window_.Show();
  }

  return did_show;
}

void Win32Window::ShowAsDebugDesktopWidget() {
  if (window_handle_ == nullptr) {
    return;
  }

  native_gantt_window_.SetPlacementMode(false);
  if (native_gantt_enabled_ && native_gantt_visible_) {
    native_gantt_window_.Show();
  }
  ShowWindow(window_handle_, SW_HIDE);
}

void Win32Window::SetNativeGanttEnabled(bool enabled) {
  native_gantt_enabled_ = enabled;

  if (!native_gantt_enabled_) {
    native_gantt_window_.Hide();
    return;
  }

  if (native_gantt_visible_) {
    native_gantt_window_.Show();
  }
}

void Win32Window::ShowNativeGanttWindow() {
  native_gantt_visible_ = true;
  if (native_gantt_enabled_) {
    native_gantt_window_.Show();
  }
}

void Win32Window::HideNativeGanttWindow() {
  native_gantt_visible_ = false;
  native_gantt_window_.Hide();
}

void Win32Window::UpdateNativeGanttTasks(
    const std::vector<NativeGanttTask>& tasks) {
  native_gantt_window_.UpdateTasks(tasks);
}

void Win32Window::SetNativeGanttTaskOpenHandler(
    std::function<void(const std::wstring&)> handler) {
  native_gantt_window_.SetTaskOpenHandler(handler);
}

void Win32Window::SetNativeGanttPosition(const std::string& position) {
  native_gantt_window_.SetPosition(NativeGanttPositionFromString(position));
}

std::string Win32Window::GetNativeGanttPosition() const {
  return NativeGanttPositionToString(native_gantt_window_.position());
}

void Win32Window::SetNativeGanttPlacementMode(bool enabled) {
  native_gantt_window_.SetPlacementMode(enabled);
}

void Win32Window::ShowAsMainWindow() {
  if (window_handle_ == nullptr) {
    return;
  }

  native_gantt_window_.SetPlacementMode(false);

  RECT work_area;
  if (!SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    ShowWindow(window_handle_, SW_SHOWNORMAL);
    if (native_gantt_enabled_ && native_gantt_visible_) {
      native_gantt_window_.Show();
    }
    return;
  }

  const int work_width = work_area.right - work_area.left;
  const int work_height = work_area.bottom - work_area.top;
  const int width = work_width < 1280 ? work_width : 1280;
  const int height = work_height < 720 ? work_height : 720;
  const int x = work_area.left + ((work_width - width) / 2);
  const int y = work_area.top + ((work_height - height) / 2);

  ShowWindow(window_handle_, SW_SHOWNORMAL);
  SetWindowPos(window_handle_, HWND_NOTOPMOST, x, y, width, height,
               SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
  BringWindowToTop(window_handle_);
  SetForegroundWindow(window_handle_);
  UpdateWindow(window_handle_);
  if (native_gantt_enabled_ && native_gantt_visible_) {
    native_gantt_window_.Show();
  }
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  if (desktop_widget_mode_ && message == kTaskbarCreatedMessage) {
    AddTrayIcon(hwnd);
    return 0;
  }

  switch (message) {
    case WM_CLOSE:
      if (desktop_widget_mode_) {
        if (native_gantt_enabled_ && native_gantt_visible_) {
          native_gantt_window_.Show();
        }
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;

    case kTrayWindowMessage:
      if (desktop_widget_mode_) {
        if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
          if (native_gantt_enabled_) {
            ShowNativeGanttWindow();
          }
        } else if (lparam == WM_RBUTTONUP) {
          const UINT command = ShowTrayMenu(
              hwnd, native_gantt_enabled_, native_gantt_visible_);
          if (command == kTrayMenuShow) {
            if (native_gantt_visible_) {
              HideNativeGanttWindow();
            } else {
              ShowNativeGanttWindow();
            }
          } else if (command == kTrayMenuMainWindow) {
            SetDesktopWidgetMode(false);
            OnMainWindowRequested();
            ShowAsMainWindow();
          } else if (command == kTrayMenuExit) {
            native_gantt_window_.Destroy();
            ExitDesktopWidget(hwnd);
          }
        }
        return 0;
      }
      break;

    case WM_MOUSEACTIVATE:
      if (desktop_widget_mode_) {
        return MA_NOACTIVATE;
      }
      break;

    case WM_DESTROY:
      if (desktop_widget_mode_) {
        RemoveTrayIcon(hwnd);
      }
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();
  native_gantt_window_.Destroy();

  if (window_handle_) {
    if (desktop_widget_mode_) {
      RemoveTrayIcon(window_handle_);
    }
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::SetDesktopWidgetMode(bool desktop_widget_mode) {
  if (desktop_widget_mode_ == desktop_widget_mode) {
    return;
  }

  desktop_widget_mode_ = desktop_widget_mode;

  if (window_handle_ == nullptr) {
    return;
  }

  if (desktop_widget_mode_) {
    AddTrayIcon(window_handle_);
  } else {
    RemoveTrayIcon(window_handle_);
  }
}

bool Win32Window::IsDesktopWidgetMode() const {
  return desktop_widget_mode_;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::OnMainWindowRequested() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
