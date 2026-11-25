import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The WinMM player uses dart:ffi, which the web build cannot compile, so the web build takes the stub.
import 'native_audio_stub.dart' if (dart.library.io) 'native_audio_io.dart';

/// Plays short sound clips (WAV bytes) on the host.
abstract class NativeAudioService {
  /// Plays [wavBytes] without blocking. Does nothing under the test runner.
  void playWav(Uint8List wavBytes);

  /// Releases the buffer of the last clip.
  void dispose();
}

final nativeAudioServiceProvider = Provider<NativeAudioService>((ref) => createNativeAudioService());
