
import 'package:flutter/services.dart';

import 'native_audio_service.dart';

/// The audio service where there is no native player (the web build): every sound is the system click.
NativeAudioService createNativeAudioService() => const _SystemClickAudioService();

class _SystemClickAudioService implements NativeAudioService {
  const _SystemClickAudioService();

  @override
  void playWav(Uint8List wavBytes) => SystemSound.play(SystemSoundType.click);

  @override
  void dispose() {}
}
