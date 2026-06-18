import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_llm/juice_llm.dart';
import 'package:juice_llm_llamacpp/juice_llm_llamacpp.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, 7));

void main() {
  group('gemmaChatFormat', () {
    test('text-only is unchanged (no markers)', () {
      final p = gemmaChatFormat(const [
        LlmMessage.system('You are the Almanac.'),
        LlmMessage.user('A quiet morning.'),
      ]);
      expect(p, isNot(contains(kMediaMarker)));
      // System folds into the first user turn.
      expect(p, contains('<start_of_turn>user\nYou are the Almanac.\n\nA quiet morning.<end_of_turn>'));
      expect(p, endsWith('<start_of_turn>model\n'));
    });

    test('one image → one marker, prepended to the turn', () {
      final p = gemmaChatFormat([
        LlmMessage.user('What is this?', images: [_bytes(4)]),
      ]);
      expect(kMediaMarker.allMatches(p).length, 1);
      // Marker comes before the user's text.
      expect(p, contains('<start_of_turn>user\n$kMediaMarker\nWhat is this?<end_of_turn>'));
    });

    test('markers count images + audio, images first', () {
      final p = gemmaChatFormat([
        LlmMessage.user('Describe.', images: [_bytes(4), _bytes(4)], audio: [_bytes(4)]),
      ]);
      // 2 images + 1 audio = 3 markers.
      expect(kMediaMarker.allMatches(p).length, 3);
    });

    test('markers attach to the right turn across multiple messages', () {
      final p = gemmaChatFormat([
        LlmMessage.user('first', images: [_bytes(4)]),
        LlmMessage.assistant('ok'),
        LlmMessage.user('second', audio: [_bytes(4)]),
      ]);
      expect(kMediaMarker.allMatches(p).length, 2);
      expect(p, contains('<start_of_turn>user\n$kMediaMarker\nfirst<end_of_turn>'));
      expect(p, contains('<start_of_turn>user\n$kMediaMarker\nsecond<end_of_turn>'));
      // The assistant turn has no marker.
      expect(p, contains('<start_of_turn>model\nok<end_of_turn>'));
    });

    test('empty content with media → marker is the whole turn', () {
      final p = gemmaChatFormat([
        LlmMessage.user('', images: [_bytes(4)]),
      ]);
      expect(p, contains('<start_of_turn>user\n$kMediaMarker<end_of_turn>'));
    });
  });
}
