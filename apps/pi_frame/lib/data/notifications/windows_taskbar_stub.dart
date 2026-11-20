// Stand-in for windows_taskbar.dart where `dart:ffi` does not exist (the web
// build of the remote-access app). Same API, no effect: the browser has no
// Windows taskbar. desktop_notification_service.dart picks the real one with
// a conditional import whenever `dart:ffi` is available.

enum WindowsTaskbarProgressState { noProgress, indeterminate, normal, error, paused }

class WindowsTaskbar {
  WindowsTaskbar._();
  static final WindowsTaskbar instance = WindowsTaskbar._();

  void initialize() {}

  void setProgressState(int hwnd, WindowsTaskbarProgressState state) {}

  void setProgressValue(int hwnd, int completed, int total) {}
}
