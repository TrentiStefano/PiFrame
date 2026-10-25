import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'startup_audio_stub.dart' if (dart.library.io) 'startup_audio_io.dart';

class StartupAudio {
  StartupAudio._();

  /// Builds a standard 44-byte RIFF/WAVE header for 16-bit mono PCM.
  static Uint8List createWav(Int16List samples, int sampleRate) {
    final byteData = ByteData(44 + samples.length * 2);

    // "RIFF"
    byteData.setUint8(0, 0x52);
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);

    // ChunkSize: 36 + subChunk2Size
    byteData.setUint32(4, 36 + samples.length * 2, Endian.little);

    // "WAVE"
    byteData.setUint8(8, 0x57);
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);

    // "fmt "
    byteData.setUint8(12, 0x66);
    byteData.setUint8(13, 0x6D);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);

    // Subchunk1Size (16 for PCM)
    byteData.setUint32(16, 16, Endian.little);
    // AudioFormat (1 for PCM)
    byteData.setUint16(20, 1, Endian.little);
    // NumChannels (1 mono)
    byteData.setUint16(22, 1, Endian.little);
    // SampleRate
    byteData.setUint32(24, sampleRate, Endian.little);
    // ByteRate (SampleRate * NumChannels * BitsPerSample/8)
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    // BlockAlign (NumChannels * BitsPerSample/8)
    byteData.setUint16(32, 2, Endian.little);
    // BitsPerSample
    byteData.setUint16(34, 16, Endian.little);

    // "data"
    byteData.setUint8(36, 0x64);
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);

    // Subchunk2Size
    byteData.setUint32(40, samples.length * 2, Endian.little);

    // Samples
    var offset = 44;
    for (var i = 0; i < samples.length; i++) {
      byteData.setInt16(offset, samples[i], Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  /// Synthesizes a crisp "ciak" clapperboard / mechanical framing snap.
  static Uint8List generateCiakWav() {
    const sampleRate = 22050;
    const durationMs = 70;
    final totalSamples = (sampleRate * (durationMs / 1000.0)).round();
    final samples = Int16List(totalSamples);
    final random = Random(42);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      // High-impact initial transient impulse with rapid exponential decay
      final envelope = exp(-t * 90.0);
      final noise = (random.nextDouble() * 2.0 - 1.0) * 0.45;
      final woodResonance =
          sin(2 * pi * 880 * t) * 0.35 + sin(2 * pi * 1420 * t) * 0.2;
      final value = (noise + woodResonance) * envelope;
      samples[i] = (value.clamp(-1.0, 1.0) * 32767).round();
    }

    return createWav(samples, sampleRate);
  }

  /// Synthesizes a soft, harmonic light hum with smooth decay.
  static Uint8List generateHumWav() {
    const sampleRate = 22050;
    const durationMs = 450;
    final totalSamples = (sampleRate * (durationMs / 1000.0)).round();
    final samples = Int16List(totalSamples);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      // Gentle attack then smooth decay
      final attack = (t < 0.05) ? (t / 0.05) : 1.0;
      final decay = exp(-t * 4.5);
      final envelope = attack * decay;

      // Warm pure tone at 220Hz (A3) with light 440Hz octave overtone
      final fundamental = sin(2 * pi * 220.0 * t);
      final overtone = sin(2 * pi * 440.0 * t) * 0.25;
      final value = (fundamental + overtone) * envelope * 0.35;
      samples[i] = (value.clamp(-1.0, 1.0) * 32767).round();
    }

    return createWav(samples, sampleRate);
  }

  static void playCiak() {
    _play(generateCiakWav());
  }

  static void playHum() {
    _play(generateHumWav());
  }

  static void _play(Uint8List wavBytes) {
    if (kIsWeb) {
      SystemSound.play(SystemSoundType.click);
      return;
    }
    playWavNative(wavBytes);
  }

  static void dispose() {
    if (!kIsWeb) {
      disposeNativeAudio();
    }
  }
}
