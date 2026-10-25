import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

typedef _PlaySoundNative = Int32 Function(
  Pointer<Void> pszSound,
  IntPtr hmod,
  Uint32 fdwSound,
);
typedef _PlaySoundDart = int Function(
  Pointer<Void> pszSound,
  int hmod,
  int fdwSound,
);

const int _sndAsync = 0x0001;
const int _sndMemory = 0x0004;

Pointer<Uint8>? _activeSoundBuffer;

void playWavNative(Uint8List wavBytes) {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return;
  }

  if (Platform.isWindows) {
    try {
      final winmm = DynamicLibrary.open('winmm.dll');
      final playSound = winmm.lookupFunction<_PlaySoundNative, _PlaySoundDart>(
        'PlaySoundW',
      );

      if (_activeSoundBuffer != null) {
        calloc.free(_activeSoundBuffer!);
        _activeSoundBuffer = null;
      }

      final ptr = calloc<Uint8>(wavBytes.length);
      final list = ptr.asTypedList(wavBytes.length);
      list.setAll(0, wavBytes);
      _activeSoundBuffer = ptr;

      playSound(ptr.cast<Void>(), 0, _sndMemory | _sndAsync);
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  } else {
    SystemSound.play(SystemSoundType.click);
  }
}

void disposeNativeAudio() {
  if (_activeSoundBuffer != null) {
    try {
      calloc.free(_activeSoundBuffer!);
    } catch (_) {}
    _activeSoundBuffer = null;
  }
}
