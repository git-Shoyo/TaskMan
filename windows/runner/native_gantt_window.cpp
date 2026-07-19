#include "native_gantt_window.h"

#include <gdiplus.h>
#include <windowsx.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <ctime>
#include <string>

namespace {

constexpr const wchar_t kNativeGanttWindowClassName[] =
    L"TASKMAN_NATIVE_GANTT_WINDOW";
constexpr const wchar_t kSettingsRegKey[] = L"Software\\TaskMan";
constexpr const wchar_t kGanttPositionRegValue[] = L"NativeGanttPosition";
constexpr const wchar_t kGanttCustomLeftRegValue[] = L"NativeGanttCustomLeft";
constexpr const wchar_t kGanttCustomTopRegValue[] = L"NativeGanttCustomTop";
constexpr const wchar_t kGanttCustomWidthRegValue[] =
    L"NativeGanttCustomWidth";
constexpr const wchar_t kGanttCustomHeightRegValue[] =
    L"NativeGanttCustomHeight";
constexpr int kVisibleDays = 7;
constexpr int kWidgetOffset = 80;
constexpr int kDefaultWidgetWidth = 560;
constexpr int kDefaultWidgetHeight = 300;
constexpr int kMinWidgetWidth = 360;
constexpr int kMinWidgetHeight = 190;
constexpr int kResizeGripSize = 14;
constexpr UINT_PTR kBackmostTimerId = 7;
constexpr UINT kBackmostTimerIntervalMs = 1000;

ULONG_PTR g_gdiplus_token = 0;
int g_gdiplus_ref_count = 0;

void StartGdiplus() {
  if (g_gdiplus_ref_count == 0) {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&g_gdiplus_token, &input, nullptr);
  }
  ++g_gdiplus_ref_count;
}

void StopGdiplus() {
  if (g_gdiplus_ref_count == 0) {
    return;
  }

  --g_gdiplus_ref_count;
  if (g_gdiplus_ref_count == 0) {
    Gdiplus::GdiplusShutdown(g_gdiplus_token);
    g_gdiplus_token = 0;
  }
}

void RegisterNativeGanttWindowClass() {
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kNativeGanttWindowClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpfnWndProc = NativeGanttWindow::WndProc;
  RegisterClass(&window_class);
}

DWORD PositionToDword(NativeGanttPosition position) {
  switch (position) {
    case NativeGanttPosition::TopRight:
      return 1;
    case NativeGanttPosition::BottomLeft:
      return 2;
    case NativeGanttPosition::BottomRight:
      return 3;
    case NativeGanttPosition::Custom:
      return 4;
    case NativeGanttPosition::TopLeft:
    default:
      return 0;
  }
}

NativeGanttPosition PositionFromDword(DWORD value) {
  switch (value) {
    case 1:
      return NativeGanttPosition::TopRight;
    case 2:
      return NativeGanttPosition::BottomLeft;
    case 3:
      return NativeGanttPosition::BottomRight;
    case 4:
      return NativeGanttPosition::Custom;
    case 0:
    default:
      return NativeGanttPosition::TopLeft;
  }
}

NativeGanttPosition LoadPosition() {
  DWORD value = 0;
  DWORD value_size = sizeof(value);
  const LSTATUS result =
      RegGetValue(HKEY_CURRENT_USER, kSettingsRegKey, kGanttPositionRegValue,
                  RRF_RT_REG_DWORD, nullptr, &value, &value_size);
  if (result != ERROR_SUCCESS) {
    return NativeGanttPosition::TopLeft;
  }
  return PositionFromDword(value);
}

bool LoadSignedDword(const wchar_t* value_name, int* value) {
  DWORD raw_value = 0;
  DWORD value_size = sizeof(raw_value);
  const LSTATUS result =
      RegGetValue(HKEY_CURRENT_USER, kSettingsRegKey, value_name,
                  RRF_RT_REG_DWORD, nullptr, &raw_value, &value_size);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  *value = static_cast<int>(static_cast<LONG>(raw_value));
  return true;
}

void SaveSignedDword(HKEY key, const wchar_t* value_name, int value) {
  const DWORD raw_value = static_cast<DWORD>(static_cast<LONG>(value));
  RegSetValueEx(key, value_name, 0, REG_DWORD,
                reinterpret_cast<const BYTE*>(&raw_value), sizeof(raw_value));
}

void SavePosition(NativeGanttPosition position) {
  HKEY key = nullptr;
  const LSTATUS create_result =
      RegCreateKeyEx(HKEY_CURRENT_USER, kSettingsRegKey, 0, nullptr, 0,
                     KEY_SET_VALUE, nullptr, &key, nullptr);
  if (create_result != ERROR_SUCCESS || key == nullptr) {
    return;
  }

  const DWORD value = PositionToDword(position);
  RegSetValueEx(key, kGanttPositionRegValue, 0, REG_DWORD,
                reinterpret_cast<const BYTE*>(&value), sizeof(value));
  RegCloseKey(key);
}

NativeGanttBounds LoadCustomBounds() {
  NativeGanttBounds bounds;
  const bool has_left =
      LoadSignedDword(kGanttCustomLeftRegValue, &bounds.left);
  const bool has_top = LoadSignedDword(kGanttCustomTopRegValue, &bounds.top);
  const bool has_width =
      LoadSignedDword(kGanttCustomWidthRegValue, &bounds.width);
  const bool has_height =
      LoadSignedDword(kGanttCustomHeightRegValue, &bounds.height);

  bounds.is_initialized = has_left && has_top && has_width && has_height;
  bounds.width = std::max(kMinWidgetWidth, bounds.width);
  bounds.height = std::max(kMinWidgetHeight, bounds.height);
  return bounds;
}

void SaveCustomBounds(const NativeGanttBounds& bounds) {
  HKEY key = nullptr;
  const LSTATUS create_result =
      RegCreateKeyEx(HKEY_CURRENT_USER, kSettingsRegKey, 0, nullptr, 0,
                     KEY_SET_VALUE, nullptr, &key, nullptr);
  if (create_result != ERROR_SUCCESS || key == nullptr) {
    return;
  }

  SaveSignedDword(key, kGanttCustomLeftRegValue, bounds.left);
  SaveSignedDword(key, kGanttCustomTopRegValue, bounds.top);
  SaveSignedDword(key, kGanttCustomWidthRegValue, bounds.width);
  SaveSignedDword(key, kGanttCustomHeightRegValue, bounds.height);
  RegCloseKey(key);
}

POINT WindowPositionForWorkArea(const RECT& work_area,
                                int width,
                                int height,
                                NativeGanttPosition position) {
  POINT point{};

  switch (position) {
    case NativeGanttPosition::TopRight:
      point.x = work_area.right - width - kWidgetOffset;
      point.y = work_area.top + kWidgetOffset;
      break;
    case NativeGanttPosition::BottomLeft:
      point.x = work_area.left + kWidgetOffset;
      point.y = work_area.bottom - height - kWidgetOffset;
      break;
    case NativeGanttPosition::BottomRight:
      point.x = work_area.right - width - kWidgetOffset;
      point.y = work_area.bottom - height - kWidgetOffset;
      break;
    case NativeGanttPosition::Custom:
    case NativeGanttPosition::TopLeft:
    default:
      point.x = work_area.left + kWidgetOffset;
      point.y = work_area.top + kWidgetOffset;
      break;
  }

  point.x =
      std::clamp(point.x, work_area.left, std::max(work_area.left,
                                                  work_area.right - width));
  point.y =
      std::clamp(point.y, work_area.top, std::max(work_area.top,
                                                  work_area.bottom - height));
  return point;
}

RECT WorkAreaForRect(const RECT& rect) {
  HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (monitor != nullptr && GetMonitorInfo(monitor, &monitor_info)) {
    return monitor_info.rcWork;
  }

  RECT work_area;
  if (!SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    work_area.left = 0;
    work_area.top = 0;
    work_area.right = kDefaultWidgetWidth + kWidgetOffset;
    work_area.bottom = kDefaultWidgetHeight + kWidgetOffset;
  }
  return work_area;
}

RECT ClampRectToWorkArea(RECT rect) {
  if (rect.left > rect.right) {
    std::swap(rect.left, rect.right);
  }
  if (rect.top > rect.bottom) {
    std::swap(rect.top, rect.bottom);
  }

  RECT work_area = WorkAreaForRect(rect);
  const int work_width =
      static_cast<int>(std::max<LONG>(1, work_area.right - work_area.left));
  const int work_height =
      static_cast<int>(std::max<LONG>(1, work_area.bottom - work_area.top));
  const int min_width = std::min(kMinWidgetWidth, work_width);
  const int min_height = std::min(kMinWidgetHeight, work_height);

  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;
  width = std::clamp(width, min_width, work_width);
  height = std::clamp(height, min_height, work_height);

  if (rect.left < work_area.left) {
    rect.left = work_area.left;
  }
  if (rect.top < work_area.top) {
    rect.top = work_area.top;
  }
  if (rect.left + width > work_area.right) {
    rect.left = work_area.right - width;
  }
  if (rect.top + height > work_area.bottom) {
    rect.top = work_area.bottom - height;
  }

  rect.right = rect.left + width;
  rect.bottom = rect.top + height;
  return rect;
}

NativeGanttBounds BoundsFromRect(const RECT& rect) {
  NativeGanttBounds bounds;
  bounds.left = rect.left;
  bounds.top = rect.top;
  bounds.width = rect.right - rect.left;
  bounds.height = rect.bottom - rect.top;
  bounds.is_initialized = true;
  return bounds;
}

std::tm LocalDay(int day_offset) {
  const auto now = std::chrono::system_clock::now();
  const auto now_time = std::chrono::system_clock::to_time_t(now);
  std::tm local{};
  localtime_s(&local, &now_time);
  local.tm_hour = 0;
  local.tm_min = 0;
  local.tm_sec = 0;
  local.tm_mday += day_offset;
  mktime(&local);
  return local;
}

std::wstring FormatShortDate(const std::tm& day) {
  wchar_t buffer[16];
  swprintf_s(buffer, L"%d/%d", day.tm_mon + 1, day.tm_mday);
  return buffer;
}

std::wstring FormatDayLabel(const std::tm& day) {
  constexpr const wchar_t* kWeekdays[] = {
      L"\u65e5", L"\u6708", L"\u706b", L"\u6c34",
      L"\u6728", L"\u91d1", L"\u571f",
  };
  wchar_t buffer[16];
  swprintf_s(buffer, L"%d %s", day.tm_mday, kWeekdays[day.tm_wday]);
  return buffer;
}

void DrawTextWithShadow(Gdiplus::Graphics& graphics,
                        const std::wstring& text,
                        const Gdiplus::Font& font,
                        const Gdiplus::RectF& rect,
                        const Gdiplus::StringFormat& format,
                        Gdiplus::Color color) {
  Gdiplus::SolidBrush shadow(Gdiplus::Color(170, 255, 255, 255));
  Gdiplus::RectF shadow_rect(rect.X + 1.0f, rect.Y + 1.0f, rect.Width,
                             rect.Height);
  graphics.DrawString(text.c_str(), -1, &font, shadow_rect, &format, &shadow);

  Gdiplus::SolidBrush brush(color);
  graphics.DrawString(text.c_str(), -1, &font, rect, &format, &brush);
}

void AddRoundedRectPath(Gdiplus::GraphicsPath& path,
                        float x,
                        float y,
                        float width,
                        float height,
                        float radius) {
  const float diameter = radius * 2.0f;
  path.AddArc(x, y, diameter, diameter, 180.0f, 90.0f);
  path.AddArc(x + width - diameter, y, diameter, diameter, 270.0f, 90.0f);
  path.AddArc(x + width - diameter, y + height - diameter, diameter, diameter,
              0.0f, 90.0f);
  path.AddArc(x, y + height - diameter, diameter, diameter, 90.0f, 90.0f);
  path.CloseFigure();
}

Gdiplus::Color TaskColor(const NativeGanttTask& task) {
  if (task.is_done) {
    return Gdiplus::Color(230, 96, 125, 139);
  }
  if (task.is_overdue) {
    return Gdiplus::Color(235, 190, 44, 52);
  }
  if (task.priority >= 4) {
    return Gdiplus::Color(235, 214, 120, 39);
  }
  return Gdiplus::Color(235, 112, 86, 131);
}

}  // namespace

NativeGanttWindow::NativeGanttWindow() {
  StartGdiplus();
  RegisterNativeGanttWindowClass();
  position_ = LoadPosition();
  custom_bounds_ = LoadCustomBounds();
}

NativeGanttWindow::~NativeGanttWindow() {
  Destroy();
  StopGdiplus();
}

void NativeGanttWindow::SetOwner(HWND owner) {
  owner_ = owner;
}

void NativeGanttWindow::SetTaskOpenHandler(
    std::function<void(const std::wstring&)> handler) {
  task_open_handler_ = handler;
}

void NativeGanttWindow::SetPosition(NativeGanttPosition position) {
  if (position != NativeGanttPosition::Custom && placement_mode_) {
    SaveCurrentCustomBounds();
    placement_mode_ = false;
    is_dragging_ = false;
    drag_mode_ = DragMode::None;
  }

  position_ = position;
  SavePosition(position_);

  if (position_ == NativeGanttPosition::Custom &&
      !custom_bounds_.is_initialized) {
    if (window_ != nullptr) {
      RECT current_rect;
      GetWindowRect(window_, &current_rect);
      custom_bounds_ = BoundsFromRect(ClampRectToWorkArea(current_rect));
    } else {
      custom_bounds_ = BoundsFromRect(DesiredWindowRect());
    }
    SaveCustomBounds(custom_bounds_);
  }

  ApplyInputMode();

  if (window_ != nullptr) {
    ApplyCurrentPosition(IsWindowVisible(window_));
  }
}

NativeGanttPosition NativeGanttWindow::position() const {
  return position_;
}

void NativeGanttWindow::SetPlacementMode(bool enabled) {
  if (enabled) {
    if (position_ != NativeGanttPosition::Custom) {
      position_ = NativeGanttPosition::Custom;
      SavePosition(position_);
    }
    if (!custom_bounds_.is_initialized) {
      custom_bounds_ = BoundsFromRect(DesiredWindowRect());
      SaveCustomBounds(custom_bounds_);
    }
  }

  placement_mode_ = enabled;
  if (!placement_mode_) {
    if (position_ == NativeGanttPosition::Custom) {
      SaveCurrentCustomBounds();
    }
    is_dragging_ = false;
    drag_mode_ = DragMode::None;
    ReleaseCapture();
  }

  if (enabled && !EnsureWindow()) {
    return;
  }

  ApplyInputMode();

  if (window_ != nullptr) {
    ApplyCurrentPosition(enabled || IsWindowVisible(window_));
  }
}

void NativeGanttWindow::UpdateTasks(
    const std::vector<NativeGanttTask>& tasks) {
  tasks_ = tasks;
  has_received_tasks_ = true;
  Render();
}

void NativeGanttWindow::Show() {
  if (!EnsureWindow()) {
    return;
  }

  ApplyCurrentPosition(true);
}

void NativeGanttWindow::Hide() {
  if (window_ != nullptr) {
    ShowWindow(window_, SW_HIDE);
  }
}

void NativeGanttWindow::Destroy() {
  if (window_ != nullptr) {
    KillTimer(window_, kBackmostTimerId);
    DestroyWindow(window_);
    window_ = nullptr;
  }
}

bool NativeGanttWindow::EnsureWindow() {
  if (window_ != nullptr) {
    return true;
  }

  const RECT bounds = DesiredWindowRect();
  width_ = bounds.right - bounds.left;
  height_ = bounds.bottom - bounds.top;
  const DWORD window_ex_style =
      WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;

  window_ = CreateWindowEx(
      window_ex_style,
      kNativeGanttWindowClassName, L"TaskMan Gantt", WS_POPUP,
      bounds.left, bounds.top, width_, height_, nullptr, nullptr,
      GetModuleHandle(nullptr), this);

  if (window_ != nullptr) {
    SetTimer(window_, kBackmostTimerId, kBackmostTimerIntervalMs, nullptr);
  }

  return window_ != nullptr;
}

void NativeGanttWindow::ApplyInputMode() {
  if (window_ == nullptr) {
    return;
  }

  LONG_PTR ex_style = GetWindowLongPtr(window_, GWL_EXSTYLE);
  ex_style &= ~WS_EX_TRANSPARENT;
  SetWindowLongPtr(window_, GWL_EXSTYLE, ex_style);
  SetWindowPos(window_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void NativeGanttWindow::ApplyCurrentPosition(bool show_window) {
  if (window_ == nullptr) {
    return;
  }

  const RECT bounds = DesiredWindowRect();
  width_ = bounds.right - bounds.left;
  height_ = bounds.bottom - bounds.top;

  const UINT flags =
      SWP_NOACTIVATE | (show_window ? SWP_SHOWWINDOW : 0);
  SetWindowPos(window_, placement_mode_ ? HWND_TOPMOST : HWND_BOTTOM,
               bounds.left, bounds.top, width_, height_, flags);
  Render();
  SendToBack();
}

void NativeGanttWindow::ApplyCustomBounds(const RECT& bounds,
                                          bool save_bounds) {
  if (window_ == nullptr) {
    return;
  }

  const RECT clamped_bounds = ClampRectToWorkArea(bounds);
  custom_bounds_ = BoundsFromRect(clamped_bounds);
  width_ = custom_bounds_.width;
  height_ = custom_bounds_.height;

  SetWindowPos(window_, placement_mode_ ? HWND_TOPMOST : HWND_BOTTOM,
               custom_bounds_.left, custom_bounds_.top, width_, height_,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  Render();
  SendToBack();

  if (save_bounds) {
    SaveCustomBounds(custom_bounds_);
  }
}

void NativeGanttWindow::SendToBack() {
  if (window_ == nullptr || placement_mode_) {
    return;
  }

  SetWindowPos(window_, HWND_BOTTOM, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER);
}

void NativeGanttWindow::SaveCurrentCustomBounds() {
  if (window_ == nullptr) {
    return;
  }

  RECT current_rect;
  GetWindowRect(window_, &current_rect);
  custom_bounds_ = BoundsFromRect(ClampRectToWorkArea(current_rect));
  SaveCustomBounds(custom_bounds_);
}

RECT NativeGanttWindow::DesiredWindowRect() const {
  RECT work_area;
  if (!SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    work_area.left = 0;
    work_area.top = 0;
    work_area.right = kDefaultWidgetWidth + kWidgetOffset;
    work_area.bottom = kDefaultWidgetHeight + kWidgetOffset;
  }

  if (position_ == NativeGanttPosition::Custom) {
    RECT custom_rect;
    if (custom_bounds_.is_initialized) {
      custom_rect.left = custom_bounds_.left;
      custom_rect.top = custom_bounds_.top;
      custom_rect.right = custom_bounds_.left + custom_bounds_.width;
      custom_rect.bottom = custom_bounds_.top + custom_bounds_.height;
    } else {
      const POINT point = WindowPositionForWorkArea(
          work_area, kDefaultWidgetWidth, kDefaultWidgetHeight,
          NativeGanttPosition::TopLeft);
      custom_rect.left = point.x;
      custom_rect.top = point.y;
      custom_rect.right = point.x + kDefaultWidgetWidth;
      custom_rect.bottom = point.y + kDefaultWidgetHeight;
    }
    return ClampRectToWorkArea(custom_rect);
  }

  const POINT point = WindowPositionForWorkArea(
      work_area, kDefaultWidgetWidth, kDefaultWidgetHeight, position_);
  RECT bounds;
  bounds.left = point.x;
  bounds.top = point.y;
  bounds.right = point.x + kDefaultWidgetWidth;
  bounds.bottom = point.y + kDefaultWidgetHeight;
  return ClampRectToWorkArea(bounds);
}

NativeGanttWindow::DragMode NativeGanttWindow::HitTestClientPoint(
    int x,
    int y) const {
  if (!placement_mode_) {
    return DragMode::None;
  }

  const bool left = x <= kResizeGripSize;
  const bool right = x >= width_ - kResizeGripSize;
  const bool top = y <= kResizeGripSize;
  const bool bottom = y >= height_ - kResizeGripSize;

  if (left && top) {
    return DragMode::ResizeTopLeft;
  }
  if (right && top) {
    return DragMode::ResizeTopRight;
  }
  if (left && bottom) {
    return DragMode::ResizeBottomLeft;
  }
  if (right && bottom) {
    return DragMode::ResizeBottomRight;
  }
  if (left) {
    return DragMode::ResizeLeft;
  }
  if (right) {
    return DragMode::ResizeRight;
  }
  if (top) {
    return DragMode::ResizeTop;
  }
  if (bottom) {
    return DragMode::ResizeBottom;
  }

  return DragMode::Move;
}

int NativeGanttWindow::HitTestTaskIndex(int x, int y) const {
  if (placement_mode_ || tasks_.empty()) {
    return -1;
  }

  constexpr float row_top = 88.0f;
  constexpr float row_height = 34.0f;
  constexpr float left = 22.0f;
  const float right = static_cast<float>(width_ - 16);
  if (x < left || x > right || y < row_top) {
    return -1;
  }

  const int max_row_count =
      std::clamp(static_cast<int>((height_ - row_top - 24.0f) / row_height),
                 1, 6);
  const int row_count =
      std::min(static_cast<int>(tasks_.size()), max_row_count);
  const int index = static_cast<int>((y - row_top) / row_height);

  if (index < 0 || index >= row_count) {
    return -1;
  }

  return index;
}

void NativeGanttWindow::UpdateCursorForPoint(int x, int y) const {
  HCURSOR cursor = LoadCursor(nullptr, IDC_ARROW);
  if (!placement_mode_ && HitTestTaskIndex(x, y) >= 0) {
    SetCursor(LoadCursor(nullptr, IDC_HAND));
    return;
  }

  switch (HitTestClientPoint(x, y)) {
    case DragMode::ResizeTopLeft:
    case DragMode::ResizeBottomRight:
      cursor = LoadCursor(nullptr, IDC_SIZENWSE);
      break;
    case DragMode::ResizeTopRight:
    case DragMode::ResizeBottomLeft:
      cursor = LoadCursor(nullptr, IDC_SIZENESW);
      break;
    case DragMode::ResizeLeft:
    case DragMode::ResizeRight:
      cursor = LoadCursor(nullptr, IDC_SIZEWE);
      break;
    case DragMode::ResizeTop:
    case DragMode::ResizeBottom:
      cursor = LoadCursor(nullptr, IDC_SIZENS);
      break;
    case DragMode::Move:
      cursor = LoadCursor(nullptr, IDC_SIZEALL);
      break;
    case DragMode::None:
    default:
      break;
  }
  SetCursor(cursor);
}

RECT NativeGanttWindow::DraggedRectForPoint(POINT screen_point) const {
  RECT bounds = drag_start_rect_;
  const int delta_x = screen_point.x - drag_start_point_.x;
  const int delta_y = screen_point.y - drag_start_point_.y;

  switch (drag_mode_) {
    case DragMode::Move:
      OffsetRect(&bounds, delta_x, delta_y);
      break;
    case DragMode::ResizeLeft:
      bounds.left += delta_x;
      break;
    case DragMode::ResizeRight:
      bounds.right += delta_x;
      break;
    case DragMode::ResizeTop:
      bounds.top += delta_y;
      break;
    case DragMode::ResizeBottom:
      bounds.bottom += delta_y;
      break;
    case DragMode::ResizeTopLeft:
      bounds.left += delta_x;
      bounds.top += delta_y;
      break;
    case DragMode::ResizeTopRight:
      bounds.right += delta_x;
      bounds.top += delta_y;
      break;
    case DragMode::ResizeBottomLeft:
      bounds.left += delta_x;
      bounds.bottom += delta_y;
      break;
    case DragMode::ResizeBottomRight:
      bounds.right += delta_x;
      bounds.bottom += delta_y;
      break;
    case DragMode::None:
    default:
      break;
  }

  return ClampRectToWorkArea(bounds);
}

void NativeGanttWindow::Render() {
  if (window_ == nullptr) {
    return;
  }

  HDC screen_dc = GetDC(nullptr);
  HDC memory_dc = CreateCompatibleDC(screen_dc);

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width_;
  bitmap_info.bmiHeader.biHeight = -height_;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS,
                                    &bits, nullptr, 0);
  HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);
  ZeroMemory(bits, static_cast<size_t>(width_) * height_ * 4);

  {
    Gdiplus::Graphics graphics(memory_dc);
    graphics.SetCompositingMode(Gdiplus::CompositingModeSourceOver);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

    Gdiplus::FontFamily preferred_font_family(L"Yu Gothic UI");
    const Gdiplus::FontFamily* font_family =
        preferred_font_family.IsAvailable()
            ? &preferred_font_family
            : Gdiplus::FontFamily::GenericSansSerif();

    Gdiplus::Font header_font(font_family, 15.0f, Gdiplus::FontStyleBold,
                              Gdiplus::UnitPixel);
    Gdiplus::Font label_font(font_family, 14.0f, Gdiplus::FontStyleBold,
                             Gdiplus::UnitPixel);
    Gdiplus::Font small_font(font_family, 13.0f, Gdiplus::FontStyleBold,
                             Gdiplus::UnitPixel);
    Gdiplus::Font bar_font(font_family, 14.0f, Gdiplus::FontStyleBold,
                           Gdiplus::UnitPixel);

    Gdiplus::StringFormat left_format;
    left_format.SetAlignment(Gdiplus::StringAlignmentNear);
    left_format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    left_format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    left_format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    Gdiplus::StringFormat center_format;
    center_format.SetAlignment(Gdiplus::StringAlignmentCenter);
    center_format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    center_format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    center_format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    Gdiplus::StringFormat right_format;
    right_format.SetAlignment(Gdiplus::StringAlignmentFar);
    right_format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    right_format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    right_format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    const float left = 22.0f;
    const float chart_left = 170.0f;
    const float chart_right = static_cast<float>(width_ - 16);
    const float chart_width = chart_right - chart_left;
    const float header_top = 20.0f;
    const float day_top = 52.0f;
    const float row_top = 88.0f;
    const float row_height = 34.0f;
    const float cell_width = chart_width / kVisibleDays;

    Gdiplus::GraphicsPath shadow_path(Gdiplus::FillModeAlternate);
    AddRoundedRectPath(shadow_path, 8.0f, 10.0f, width_ - 16.0f,
                       height_ - 18.0f, 18.0f);
    Gdiplus::SolidBrush shadow_brush(Gdiplus::Color(45, 0, 0, 0));
    graphics.FillPath(&shadow_brush, &shadow_path);

    Gdiplus::GraphicsPath background_path(Gdiplus::FillModeAlternate);
    AddRoundedRectPath(background_path, 6.0f, 6.0f, width_ - 12.0f,
                       height_ - 12.0f, 18.0f);
    Gdiplus::SolidBrush background_brush(
        Gdiplus::Color(242, 255, 255, 255));
    Gdiplus::Pen background_border(Gdiplus::Color(150, 210, 214, 222), 1.0f);
    graphics.FillPath(&background_brush, &background_path);
    graphics.DrawPath(&background_border, &background_path);

    if (placement_mode_) {
      Gdiplus::Pen placement_border(Gdiplus::Color(255, 38, 116, 184), 2.0f);
      graphics.DrawPath(&placement_border, &background_path);

      Gdiplus::SolidBrush handle_brush(Gdiplus::Color(255, 38, 116, 184));
      const float handle_size = 8.0f;
      const float handle_inset = 14.0f;
      graphics.FillRectangle(&handle_brush, handle_inset, handle_inset,
                             handle_size, handle_size);
      graphics.FillRectangle(&handle_brush, width_ - handle_inset - handle_size,
                             handle_inset, handle_size, handle_size);
      graphics.FillRectangle(&handle_brush, handle_inset,
                             height_ - handle_inset - handle_size,
                             handle_size, handle_size);
      graphics.FillRectangle(&handle_brush, width_ - handle_inset - handle_size,
                             height_ - handle_inset - handle_size,
                             handle_size, handle_size);
    }

    Gdiplus::Color text_color(255, 72, 34, 88);
    Gdiplus::Color grid_color(145, 112, 86, 131);
    Gdiplus::Color light_grid_color(85, 112, 86, 131);

    const auto first_day = LocalDay(0);
    const auto last_day = LocalDay(6);
    const std::wstring range =
        FormatShortDate(first_day) + L" - " + FormatShortDate(last_day);
    DrawTextWithShadow(graphics, range, header_font,
                       Gdiplus::RectF(chart_left, header_top, chart_width,
                                      22.0f),
                       right_format, text_color);

    Gdiplus::Pen grid_pen(grid_color, 1.0f);
    Gdiplus::Pen light_grid_pen(light_grid_color, 1.0f);

    for (int index = 0; index < kVisibleDays; ++index) {
      const float x = chart_left + index * cell_width;
      const auto day = LocalDay(index);
      DrawTextWithShadow(graphics, FormatDayLabel(day), small_font,
                         Gdiplus::RectF(x, day_top, cell_width, 24.0f),
                         center_format, text_color);
      graphics.DrawLine(index == 0 ? &grid_pen : &light_grid_pen, x,
                        row_top - 8.0f, x, height_ - 20.0f);
    }
    graphics.DrawLine(&grid_pen, chart_right, row_top - 8.0f, chart_right,
                      height_ - 20.0f);

    if (!has_received_tasks_) {
      DrawTextWithShadow(graphics, L"\u8aad\u307f\u8fbc\u307f\u4e2d",
                         label_font,
                         Gdiplus::RectF(left, 120.0f, width_ - 44.0f, 28.0f),
                         center_format, text_color);
    } else if (tasks_.empty()) {
      DrawTextWithShadow(
          graphics,
          L"7\u65e5\u4ee5\u5185\u306e\u30bf\u30b9\u30af\u306f"
          L"\u3042\u308a\u307e\u305b\u3093",
          label_font,
                         Gdiplus::RectF(left, 120.0f, width_ - 44.0f, 28.0f),
                         center_format, text_color);
    }

    const int max_row_count =
        std::clamp(static_cast<int>((height_ - row_top - 24.0f) / row_height),
                   1, 6);
    const int row_count =
        std::min(static_cast<int>(tasks_.size()), max_row_count);
    for (int index = 0; index < row_count; ++index) {
      const NativeGanttTask& task = tasks_[index];
      const float y = row_top + index * row_height;
      DrawTextWithShadow(graphics, task.title, label_font,
                         Gdiplus::RectF(left, y, chart_left - left - 12.0f,
                                        row_height - 2.0f),
                         left_format, text_color);

      const int start = std::clamp(task.start_offset, 0, 6);
      const int end = std::clamp(task.end_offset, 0, 6);
      const int first = std::min(start, end);
      const int last = std::max(start, end);
      const float bar_left = chart_left + first * cell_width + 4.0f;
      const float bar_width = (last - first + 1) * cell_width - 8.0f;
      const float bar_top = y + 7.0f;
      const float bar_height = 22.0f;

      Gdiplus::GraphicsPath path(Gdiplus::FillModeAlternate);
      AddRoundedRectPath(path, bar_left, bar_top, bar_width, bar_height,
                         bar_height / 2.0f);
      Gdiplus::SolidBrush bar_brush(TaskColor(task));
      graphics.FillPath(&bar_brush, &path);

      const std::wstring bar_label =
          task.label.empty()
              ? std::to_wstring(task.completion_percent) + L"%"
              : task.label;
      Gdiplus::SolidBrush bar_text(Gdiplus::Color(255, 255, 255, 255));
      graphics.DrawString(bar_label.c_str(), -1, &bar_font,
                          Gdiplus::RectF(bar_left + 10.0f, bar_top, bar_width - 16.0f,
                                         bar_height),
                          &left_format, &bar_text);
    }
  }

  POINT source_position{0, 0};
  SIZE window_size{width_, height_};
  RECT window_rect;
  GetWindowRect(window_, &window_rect);
  POINT window_position{window_rect.left, window_rect.top};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;

  UpdateLayeredWindow(window_, screen_dc, &window_position, &window_size,
                      memory_dc, &source_position, 0, &blend, ULW_ALPHA);

  SelectObject(memory_dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);

  SendToBack();
}

LRESULT CALLBACK NativeGanttWindow::WndProc(HWND window,
                                            UINT message,
                                            WPARAM wparam,
                                            LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    auto that =
        static_cast<NativeGanttWindow*>(create_struct->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(that));
    that->window_ = window;
  } else if (auto that = reinterpret_cast<NativeGanttWindow*>(
                 GetWindowLongPtr(window, GWLP_USERDATA))) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT NativeGanttWindow::MessageHandler(HWND window,
                                          UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam) noexcept {
  switch (message) {
    case WM_TIMER:
      if (wparam == kBackmostTimerId) {
        SendToBack();
        return 0;
      }
      break;
    case WM_WINDOWPOSCHANGING:
      if (!placement_mode_) {
        auto window_position = reinterpret_cast<WINDOWPOS*>(lparam);
        window_position->hwndInsertAfter = HWND_BOTTOM;
        window_position->flags &= ~SWP_NOZORDER;
        window_position->flags |= SWP_NOACTIVATE;
      }
      break;
    case WM_LBUTTONDOWN:
      if (placement_mode_) {
        const int x = GET_X_LPARAM(lparam);
        const int y = GET_Y_LPARAM(lparam);
        drag_mode_ = HitTestClientPoint(x, y);
        if (drag_mode_ == DragMode::None) {
          return 0;
        }

        POINT screen_point{x, y};
        ClientToScreen(window, &screen_point);
        drag_start_point_ = screen_point;
        GetWindowRect(window, &drag_start_rect_);
        is_dragging_ = true;
        SetCapture(window);
        UpdateCursorForPoint(x, y);
        return 0;
      }
      break;
    case WM_MOUSEMOVE:
      if (placement_mode_) {
        const int x = GET_X_LPARAM(lparam);
        const int y = GET_Y_LPARAM(lparam);
        if (is_dragging_) {
          POINT screen_point{x, y};
          ClientToScreen(window, &screen_point);
          ApplyCustomBounds(DraggedRectForPoint(screen_point), false);
          return 0;
        }

        UpdateCursorForPoint(x, y);
        return 0;
      }
      break;
    case WM_LBUTTONUP:
      if (placement_mode_ && is_dragging_) {
        const int x = GET_X_LPARAM(lparam);
        const int y = GET_Y_LPARAM(lparam);
        POINT screen_point{x, y};
        ClientToScreen(window, &screen_point);
        ApplyCustomBounds(DraggedRectForPoint(screen_point), true);
        is_dragging_ = false;
        drag_mode_ = DragMode::None;
        ReleaseCapture();
        UpdateCursorForPoint(x, y);
        return 0;
      }
      if (!placement_mode_) {
        const int x = GET_X_LPARAM(lparam);
        const int y = GET_Y_LPARAM(lparam);
        const int task_index = HitTestTaskIndex(x, y);
        if (task_index >= 0 && task_index < static_cast<int>(tasks_.size())) {
          const auto& task_id = tasks_[task_index].id;
          if (!task_id.empty() && task_open_handler_) {
            task_open_handler_(task_id);
          }
          return 0;
        }
      }
      break;
    case WM_CAPTURECHANGED:
      if (placement_mode_ && is_dragging_) {
        SaveCurrentCustomBounds();
        is_dragging_ = false;
        drag_mode_ = DragMode::None;
        return 0;
      }
      break;
    case WM_SETCURSOR:
      {
        POINT cursor_position;
        GetCursorPos(&cursor_position);
        ScreenToClient(window, &cursor_position);
        UpdateCursorForPoint(cursor_position.x, cursor_position.y);
        return TRUE;
      }
      break;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
      ApplyCurrentPosition(IsWindowVisible(window) != FALSE);
      return 0;
    case WM_DESTROY:
      if (window_ == window) {
        window_ = nullptr;
      }
      return 0;
  }

  return DefWindowProc(window, message, wparam, lparam);
}
