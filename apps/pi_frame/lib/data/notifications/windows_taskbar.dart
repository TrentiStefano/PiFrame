import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

enum WindowsTaskbarProgressState { noProgress, indeterminate, normal, error, paused }

/// Direct Win32 COM implementation of [ITaskbarList3] for Windows taskbar progress
/// indicators without depending on plugin C++ code that may have null dereferences.
class WindowsTaskbar {
  WindowsTaskbar._();
  static final WindowsTaskbar instance = WindowsTaskbar._();

  Pointer<Void>? _taskbarList;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    try {
      final ole32 = DynamicLibrary.open('ole32.dll');
      final coInitializeEx = ole32
          .lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>('CoInitializeEx');
      final coCreateInstance = ole32
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Pointer<Void>, Uint32, Pointer<Uint8>, Pointer<Pointer<Void>>),
            int Function(Pointer<Uint8>, Pointer<Void>, int, Pointer<Uint8>, Pointer<Pointer<Void>>)
          >('CoCreateInstance');

      // COINIT_APARTMENTTHREADED = 0x2
      coInitializeEx(nullptr, 0x2);

      // CLSID_TaskbarList: {56FDF344-FD6D-11D0-958A-006097C9A090}
      final clsid = calloc<Uint8>(16);
      const clsidBytes = [
        0x44,
        0xF3,
        0xFD,
        0x56,
        0x6D,
        0xFD,
        0xD0,
        0x11,
        0x95,
        0x8A,
        0x00,
        0x60,
        0x97,
        0xC9,
        0xA0,
        0x90,
      ];
      for (var i = 0; i < 16; i++) {
        clsid[i] = clsidBytes[i];
      }

      // IID_ITaskbarList3: {EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF}
      final iid = calloc<Uint8>(16);
      const iidBytes = [0x91, 0xFB, 0x1A, 0xEA, 0x28, 0x9E, 0x86, 0x4B, 0x90, 0xE9, 0x9E, 0x9F, 0x8A, 0x5E, 0xEF, 0xAF];
      for (var i = 0; i < 16; i++) {
        iid[i] = iidBytes[i];
      }

      final ppTaskbar = calloc<Pointer<Void>>();
      const clsctxInprocServer = 0x1;
      final hr = coCreateInstance(clsid, nullptr, clsctxInprocServer, iid, ppTaskbar);
      calloc.free(clsid);
      calloc.free(iid);

      if (hr == 0 && ppTaskbar.value != nullptr) {
        _taskbarList = ppTaskbar.value;
        final vtable = _taskbarList!.cast<Pointer<Pointer<Void>>>().value;
        // HrInit is slot 3
        final hrInitPtr = (vtable + 3).value;
        final hrInitFn = hrInitPtr
            .cast<NativeFunction<Int32 Function(Pointer<Void>)>>()
            .asFunction<int Function(Pointer<Void>)>();
        hrInitFn(_taskbarList!);
      }
      calloc.free(ppTaskbar);
    } catch (e) {
      debugPrint('Failed to initialize Windows ITaskbarList3: $e');
    }
  }

  void setProgressState(int hwnd, WindowsTaskbarProgressState state) {
    if (hwnd == 0) return;
    initialize();
    final taskbar = _taskbarList;
    if (taskbar == null || taskbar == nullptr) return;

    try {
      final vtable = taskbar.cast<Pointer<Pointer<Void>>>().value;
      // SetProgressState is slot 10
      final setProgressStatePtr = (vtable + 10).value;
      final setProgressStateFn = setProgressStatePtr
          .cast<NativeFunction<Int32 Function(Pointer<Void>, IntPtr, Int32)>>()
          .asFunction<int Function(Pointer<Void>, int, int)>();

      int flag;
      switch (state) {
        case WindowsTaskbarProgressState.noProgress:
          flag = 0x0;
          break;
        case WindowsTaskbarProgressState.indeterminate:
          flag = 0x1;
          break;
        case WindowsTaskbarProgressState.normal:
          flag = 0x2;
          break;
        case WindowsTaskbarProgressState.error:
          flag = 0x4;
          break;
        case WindowsTaskbarProgressState.paused:
          flag = 0x8;
          break;
      }
      setProgressStateFn(taskbar, hwnd, flag);
    } catch (e) {
      debugPrint('Failed to set Windows taskbar progress state: $e');
    }
  }

  void setProgressValue(int hwnd, int completed, int total) {
    if (hwnd == 0) return;
    initialize();
    final taskbar = _taskbarList;
    if (taskbar == null || taskbar == nullptr) return;

    try {
      final vtable = taskbar.cast<Pointer<Pointer<Void>>>().value;
      // SetProgressValue is slot 9
      final setProgressValuePtr = (vtable + 9).value;
      final setProgressValueFn = setProgressValuePtr
          .cast<NativeFunction<Int32 Function(Pointer<Void>, IntPtr, Uint64, Uint64)>>()
          .asFunction<int Function(Pointer<Void>, int, int, int)>();

      setProgressValueFn(taskbar, hwnd, completed, total);
    } catch (e) {
      debugPrint('Failed to set Windows taskbar progress value: $e');
    }
  }
}
