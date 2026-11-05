import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

// Retains counters/fingerprint only, never decompressed chunks.
class _DiscardingSink extends ByteConversionSink {
  _DiscardingSink({this.limit});

  final int? limit;
  int bytes = 0;
  int deliveries = 0;
  int fingerprint = 0;
  bool closed = false;

  @override
  void add(List<int> chunk) {
    deliveries++;
    if (limit != null && bytes + chunk.length > limit!) {
      throw StateError('Output limit exceeded');
    }
    for (final byte in chunk) {
      fingerprint = ((fingerprint * 31) + byte) & 0xffffffff;
    }
    bytes += chunk.length;
  }

  @override
  void close() => closed = true;
}

class _Observation {
  _Observation(this.output);
  final _DiscardingSink output;
  Object? addError;
  Object? closeError;
  int inputAccepted = 0;
}

_Observation _decode(List<int> data, int chunkSize, {int? outputLimit}) {
  final output = _DiscardingSink(limit: outputLimit);
  final observation = _Observation(output);
  final decoder = ZLibCodec(raw: true).decoder.startChunkedConversion(output);
  for (var start = 0; start < data.length; start += chunkSize) {
    final end = math.min(start + chunkSize, data.length);
    try {
      decoder.add(data.sublist(start, end));
      observation.inputAccepted = end;
    } catch (error) {
      observation.addError = error;
      break;
    }
  }
  // Intentionally call close even after an add failure to observe its behavior.
  try {
    decoder.close();
  } catch (error) {
    observation.closeError = error;
  }
  return observation;
}

void main() {
  final payload =
      utf8.encode(List.filled(256, 'HealthMAP raw deflate test.').join());
  final secondPayload = utf8.encode('SECOND STREAM');
  final compressed = ZLibCodec(raw: true).encode(payload);
  final second = ZLibCodec(raw: true).encode(secondPayload);
  final expected = _DiscardingSink()..add(payload);
  final scenarios = <String, List<int>>{
    'valid': compressed,
    // Remove the final byte of this concrete stream; output matching does not
    // establish that its end marker was consumed.
    'truncated final byte': compressed.sublist(0, compressed.length - 1),
    'trailing garbage': [...compressed, 0xde, 0xad, 0xbe, 0xef],
    'concatenated streams': [...compressed, ...second],
    // BTYPE=3 is invalid, making this a deterministic corrupted first block.
    'corrupted block': [(compressed.first & ~6) | 6, ...compressed.skip(1)],
  };

  for (final scenario in scenarios.entries) {
    for (final chunkSize in [1, 2, 7, 64, 4096]) {
      test('${scenario.key}, input chunk $chunkSize', () {
        final result = _decode(scenario.value, chunkSize);
        final matches = result.output.bytes == expected.bytes &&
            result.output.fingerprint == expected.fingerprint;
        final accepted = result.addError == null &&
            result.closeError == null &&
            result.inputAccepted == scenario.value.length;
        // Print experimental outcomes independently of the assertions below.
        // ignore: avoid_print
        print(jsonEncode({
          'scenario': scenario.key,
          'chunkSize': chunkSize,
          'compressedBytes': scenario.value.length,
          'inputAccepted': result.inputAccepted,
          'addError': result.addError?.toString(),
          'closeError': result.closeError?.toString(),
          'outputBytes': result.output.bytes,
          'expectedOutput': matches,
          'sinkClosed': result.output.closed,
          'acceptedWithoutError': accepted,
        }));
        if (scenario.key == 'valid') {
          expect(result.addError, isNull);
          expect(result.closeError, isNull);
          expect(matches, isTrue);
          expect(result.output.closed, isTrue);
          expect(result.output.deliveries, greaterThan(0));
        } else if (scenario.key == 'corrupted block') {
          expect(result.addError ?? result.closeError, isNotNull);
          expect(matches, isFalse);
        }
        // Truncation/trailing results are observations, not assumptions about
        // guarantees absent from the public decoder contract.
      });
    }
  }

  for (final chunkSize in [1, 7, 4096]) {
    test('output sink abort, input chunk $chunkSize', () {
      final result = _decode(compressed, chunkSize, outputLimit: 16);
      // ignore: avoid_print
      print(jsonEncode({
        'scenario': 'sink limit',
        'chunkSize': chunkSize,
        'addError': result.addError?.toString(),
        'closeError': result.closeError?.toString(),
        'outputBytes': result.output.bytes,
        'sinkClosed': result.output.closed,
      }));
      expect(result.addError ?? result.closeError, isA<StateError>());
      expect(result.output.bytes, lessThanOrEqualTo(16));
    });
  }
}
