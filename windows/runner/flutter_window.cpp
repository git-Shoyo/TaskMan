#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }

  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                       0);
  if (size <= 0) {
    return L"";
  }

  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

const flutter::EncodableValue* FindMapValue(
    const flutter::EncodableMap& map,
    const char* key) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return nullptr;
  }
  return &iterator->second;
}

std::wstring ReadWideString(const flutter::EncodableMap& map,
                            const char* key) {
  const auto* value = FindMapValue(map, key);
  if (value == nullptr) {
    return L"";
  }

  if (const auto* text = std::get_if<std::string>(value)) {
    return Utf8ToWide(*text);
  }
  return L"";
}

int ReadInt(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindMapValue(map, key);
  if (value == nullptr) {
    return 0;
  }

  if (const auto integer = value->TryGetLongValue()) {
    return static_cast<int>(*integer);
  }
  return 0;
}

bool ReadBool(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindMapValue(map, key);
  if (value == nullptr) {
    return false;
  }

  if (const auto* boolean = std::get_if<bool>(value)) {
    return *boolean;
  }
  return false;
}

std::vector<NativeGanttTask> ParseNativeGanttTasks(
    const flutter::EncodableValue* arguments) {
  std::vector<NativeGanttTask> tasks;
  if (arguments == nullptr) {
    return tasks;
  }

  const auto* list = std::get_if<flutter::EncodableList>(arguments);
  if (list == nullptr) {
    return tasks;
  }

  for (const auto& item : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (map == nullptr) {
      continue;
    }

    NativeGanttTask task;
    task.id = ReadWideString(*map, "id");
    task.title = ReadWideString(*map, "title");
    task.label = ReadWideString(*map, "label");
    task.start_offset = ReadInt(*map, "startOffset");
    task.end_offset = ReadInt(*map, "endOffset");
    task.completion_percent = ReadInt(*map, "completionPercent");
    task.priority = ReadInt(*map, "priority");
    task.is_done = ReadBool(*map, "isDone");
    task.is_overdue = ReadBool(*map, "isOverdue");
    tasks.push_back(task);
  }

  return tasks;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "taskman/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->Resize(5);
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "updateNativeGanttTasks") {
          UpdateNativeGanttTasks(ParseNativeGanttTasks(call.arguments()));
          result->Success();
          return;
        }

        if (call.method_name() == "getNativeGanttPosition") {
          result->Success(flutter::EncodableValue(GetNativeGanttPosition()));
          return;
        }

        if (call.method_name() == "setNativeGanttPosition") {
          const auto* arguments = call.arguments();
          if (arguments != nullptr) {
            if (const auto* position = std::get_if<std::string>(arguments)) {
              SetNativeGanttPosition(*position);
            }
          }
          result->Success();
          return;
        }

        if (call.method_name() == "setNativeGanttPlacementMode") {
          const auto* arguments = call.arguments();
          if (arguments != nullptr) {
            if (const auto* enabled = std::get_if<bool>(arguments)) {
              SetNativeGanttPlacementMode(*enabled);
            }
          }
          result->Success();
          return;
        }

        result->NotImplemented();
      });
  SetNativeGanttTaskOpenHandler(
      [this](const std::wstring& task_id) { OpenNativeGanttTask(task_id); });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ShowDesktopWidgetView() {
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "showDesktopWidget", std::make_unique<flutter::EncodableValue>());
  }
}

void FlutterWindow::ShowMainWindowView() {
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "showMainWindow", std::make_unique<flutter::EncodableValue>());
  }
}

void FlutterWindow::OpenNativeGanttTask(const std::wstring& task_id) {
  if (task_id.empty() || !window_channel_) {
    return;
  }

  if (IsDesktopWidgetMode()) {
    SetDesktopWidgetMode(false);
    ShowMainWindowView();
    ShowAsMainWindow();
  } else if (HWND window = GetHandle()) {
    if (IsIconic(window)) {
      ShowWindow(window, SW_RESTORE);
    } else if (!IsWindowVisible(window)) {
      ShowWindow(window, SW_SHOWNORMAL);
    }
    BringWindowToTop(window);
    SetForegroundWindow(window);
    UpdateWindow(window);
  }

  window_channel_->InvokeMethod(
      "openNativeGanttTask",
      std::make_unique<flutter::EncodableValue>(
          flutter::EncodableValue(Utf8FromUtf16(task_id.c_str()))));
}

void FlutterWindow::OnMainWindowRequested() {
  ShowMainWindowView();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && !IsDesktopWidgetMode()) {
    SetDesktopWidgetMode(true);
    ShowAsDebugDesktopWidget();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
