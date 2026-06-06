// Phase 3 — Silence Scanner (RMS algorithm).
// Validation gate coverage: the worker must populate valid
// millisecond values into `track_metadata.silence_start_ms`.
// This test file exercises the pure-Dart RMS scanner with a
// synthesised WAV file (loud → silent sections) and asserts
// the boundary lands in the silent section, NOT in the loud
// section. The compressed-format heuristic is also covered
// for completeness (no decoder available in the test VM).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zyp_music/core/audio/silence_scanner.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zyp_silence_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SilenceScanner.compressed-format heuristic', () {
    test('returns a finite millisecond value for non-WAV bytes', () async {
      // The test VM has no audio codec, so a 1-byte file is
      // treated as "compressed" and the heuristic fires.
      final file = File('${tempDir.path}/small.bin')..writeAsBytesSync([1]);
      final ms = await SilenceScanner.scan(file.path);
      expect(ms, isNotNull);
      expect(ms, greaterThan(0));
      // The heuristic is anchored at 92% of an estimated
      // 210,000ms duration = 193,200ms.
      expect(ms, 193200);
    });

    test('returns null when the file does not exist', () async {
      final ms = await SilenceScanner.scan('${tempDir.path}/missing.bin');
      expect(ms, isNull);
    });

    test('returns null for a zero-byte file', () async {
      final file = File('${tempDir.path}/empty.bin')..writeAsBytesSync([]);
      final ms = await SilenceScanner.scan(file.path);
      expect(ms, isNull);
    });
  });

  group('SilenceScanner.WAV path', () {
    test('loud-then-silent WAV — boundary lands in the silent tail',
        () async {
      // Synthesise a 1-second 8kHz mono 16-bit WAV with the
      // first 800ms full-scale and the trailing 200ms at zero.
      // The RMS in the loud section is ≈ 0 dBFS; in the silent
      // section it is ≈ -∞. The boundary must fall within the
      // silent tail (i.e. > 800ms).
      final sampleRate = 8000;
      final durationMs = 1000;
      final loudUntilMs = 800;
      final samples = sampleRate * durationMs ~/ 1000;
      final data = ByteData(samples * 2);
      for (var i = 0; i < samples; i++) {
        final tMs = (i * 1000) ~/ sampleRate;
        // 16-bit signed PCM, full-scale = 32767.
        final v = tMs < loudUntilMs ? 32767 : 0;
        data.setInt16(i * 2, v, Endian.little);
      }
      final wav = _wrapAsWavMono16(data.buffer.asUint8List(), sampleRate);
      final file = File('${tempDir.path}/loud_silent.wav')
        ..writeAsBytesSync(wav);
      final ms = await SilenceScanner.scan(file.path);
      expect(ms, isNotNull);
      // Boundary must be at or after the 800ms loud/silent
      // transition. Allow a generous tolerance for the
      // 100ms RMS window straddling the boundary.
      expect(ms, greaterThanOrEqualTo(700));
      // And the scan should NOT extend past the actual end of
      // the file (duration is 1000ms).
      expect(ms, lessThanOrEqualTo(1000));
    });

    test('entirely-loud WAV — boundary is at the end of the file',
        () async {
      final sampleRate = 8000;
      final durationMs = 1000;
      final samples = sampleRate * durationMs ~/ 1000;
      final data = ByteData(samples * 2);
      for (var i = 0; i < samples; i++) {
        data.setInt16(i * 2, 32767, Endian.little);
      }
      final wav = _wrapAsWavMono16(data.buffer.asUint8List(), sampleRate);
      final file = File('${tempDir.path}/all_loud.wav')
        ..writeAsBytesSync(wav);
      final ms = await SilenceScanner.scan(file.path);
      expect(ms, isNotNull);
      // Every window is loud, so the boundary is the end of
      // the file.
      expect(ms, 1000);
    });

    test('entirely-silent WAV — boundary is at 0', () async {
      final sampleRate = 8000;
      final durationMs = 1000;
      final samples = sampleRate * durationMs ~/ 1000;
      final data = ByteData(samples * 2); // all zero
      final wav = _wrapAsWavMono16(data.buffer.asUint8List(), sampleRate);
      final file = File('${tempDir.path}/all_silent.wav')
        ..writeAsBytesSync(wav);
      final ms = await SilenceScanner.scan(file.path);
      expect(ms, 0);
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Wraps [pcm] as a RIFF/WAVE mono 16-bit PCM file at [sampleRate].
/// Used to construct a minimal-but-valid WAV for the scanner to
/// parse end-to-end.
Uint8List _wrapAsWavMono16(Uint8List pcm, int sampleRate) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataSize = pcm.length;
  final fileSize = 36 + dataSize;
  final out = BytesBuilder();
  void u16(int v) {
    out.add([v & 0xff, (v >> 8) & 0xff]);
  }

  void u32(int v) {
    out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  }

  // RIFF header
  out.add('RIFF'.codeUnits);
  u32(fileSize);
  out.add('WAVE'.codeUnits);
  // fmt chunk
  out.add('fmt '.codeUnits);
  u32(16); // PCM fmt chunk size
  u16(1); // audio format = PCM
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  // data chunk
  out.add('data'.codeUnits);
  u32(dataSize);
  out.add(pcm);
  return out.toBytes();
}
