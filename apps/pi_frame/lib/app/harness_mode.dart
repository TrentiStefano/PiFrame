/// Whether this process was started through the developer-only UI harness.
///
/// Set before bootstrapping the app so desktop services can avoid user-facing
/// side effects such as persisting window geometry or activating the window.
bool _harnessMode = false;

bool get isHarnessMode => _harnessMode;

void enableHarnessMode() {
  _harnessMode = true;
}
