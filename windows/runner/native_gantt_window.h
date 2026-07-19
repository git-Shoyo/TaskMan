#ifndef RUNNER_NATIVE_GANTT_WINDOW_H_
#define RUNNER_NATIVE_GANTT_WINDOW_H_

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

enum class NativeGanttPosition {
  TopLeft,
  TopRight,
  BottomLeft,
  BottomRight,
  Custom,
};

struct NativeGanttTask {
  std::wstring id;
  std::wstring title;
  std::wstring label;
  int start_offset = 0;
  int end_offset = 0;
  int completion_percent = 0;
  int priority = 0;
  bool is_done = false;
  bool is_overdue = false;
};

struct NativeGanttBounds {
  int left = 0;
  int top = 0;
  int width = 560;
  int height = 300;
  bool is_initialized = false;
};

class NativeGanttWindow {
 public:
  NativeGanttWindow();
  ~NativeGanttWindow();

  void SetOwner(HWND owner);
  void SetTaskOpenHandler(std::function<void(const std::wstring&)> handler);
  void SetPosition(NativeGanttPosition position);
  NativeGanttPosition position() const;
  void SetPlacementMode(bool enabled);
  void UpdateTasks(const std::vector<NativeGanttTask>& tasks);
  void Show();
  void Hide();
  void Destroy();

  static LRESULT CALLBACK WndProc(HWND window,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam) noexcept;

 private:
  enum class DragMode {
    None,
    Move,
    ResizeLeft,
    ResizeRight,
    ResizeTop,
    ResizeBottom,
    ResizeTopLeft,
    ResizeTopRight,
    ResizeBottomLeft,
    ResizeBottomRight,
  };

  bool EnsureWindow();
  void ApplyInputMode();
  void ApplyCurrentPosition(bool show_window);
  void ApplyCustomBounds(const RECT& bounds, bool save_bounds);
  void SendToBack();
  void Render();
  void SaveCurrentCustomBounds();
  RECT DesiredWindowRect() const;
  DragMode HitTestClientPoint(int x, int y) const;
  int HitTestTaskIndex(int x, int y) const;
  void UpdateCursorForPoint(int x, int y) const;
  RECT DraggedRectForPoint(POINT screen_point) const;

  LRESULT MessageHandler(HWND window,
                         UINT message,
                         WPARAM wparam,
                         LPARAM lparam) noexcept;

  HWND owner_ = nullptr;
  HWND window_ = nullptr;
  std::vector<NativeGanttTask> tasks_;
  std::function<void(const std::wstring&)> task_open_handler_;
  NativeGanttPosition position_ = NativeGanttPosition::TopLeft;
  NativeGanttBounds custom_bounds_;
  bool has_received_tasks_ = false;
  bool placement_mode_ = false;
  bool is_dragging_ = false;
  DragMode drag_mode_ = DragMode::None;
  POINT drag_start_point_{};
  RECT drag_start_rect_{};
  int width_ = 560;
  int height_ = 300;
};

#endif  // RUNNER_NATIVE_GANTT_WINDOW_H_
