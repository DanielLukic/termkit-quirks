import 'package:termparser/termparser.dart';
import 'package:test/test.dart';

import 'mock_provider.dart';

void main() {
  void listAdvance(Engine engine, Provider provider, List<int> input, {bool more = false}) {
    for (var i = 0; i < input.length; i++) {
      engine.advance(provider, input[i], more: (i < (input.length - 1)) || more);
    }
  }

  void stringAdvance(Engine engine, Provider provider, String input, {bool more = false}) {
    final x = input.split('');
    for (var i = 0; i < input.length; i++) {
      engine.advance(provider, x[i].codeUnitAt(0), more: (i < (input.length - 1)) || more);
    }
  }

  group('ESC >', () {
    test('char', () {
      final eng = Engine();
      final cp = MockProvider(); // MockCharProvider();

      // No more input means that the Esc character should be dispatched immediately
      eng.advance(cp, 0x1b);
      expect(cp.chars, ['\x1b']);

      // There's more input so the machine should wait before dispatching Esc character
      eng.advance(cp, 0x1b, more: true);
      expect(cp.chars, ['\x1b']);

      // Another Esc character, but no more input, machine should dispatch the postponed Esc
      // character and the new one too.
      eng.advance(cp, 0x1b);
      expect(cp.chars, ['\x1b', '\x1b', '\x1b']);
    });

    test('without intermediates', () {
      final eng = Engine();
      final cp = MockProvider(); // MockEscProvider();

      const input = '\x1B0\x1B~';
      stringAdvance(eng, cp, input);

      expect(cp.chars.length, 2);
      expect(cp.chars[0], '0');
      expect(cp.chars[1], '~');
    });

    test('W', () {
      final eng = Engine();
      final cp = MockProvider(); // MockEscProvider();

      const input = 'a\x1BDc';
      stringAdvance(eng, cp, input);

      expect(cp.chars.length, 3);
      expect(cp.chars[0], 'a');
      expect(cp.chars[1], 'D');
      expect(cp.chars[2], 'c');
    });
  });

  group('CSI >', () {
    test('without parameters', () {
      final eng = Engine();
      final cp = MockProvider(); // MockCsiProvider();

      listAdvance(eng, cp, [0x1b, 0x5b, 0x6d]);

      expect(cp.params.length, 1);
      expect(cp.params[0], <int>[]);
      expect(cp.chars.length, 1);
      expect(cp.chars[0], 'm');
    });

    test('with two default parameters', () {
      final eng = Engine();
      final cp = MockProvider(); // MockCsiProvider();

      const input = '\x1b\x5b;m';
      stringAdvance(eng, cp, input);

      expect(cp.params.length, 1);
      expect(cp.params[0], <int>[0, 0]); // default parameters values
      expect(cp.chars.length, 1);
      expect(cp.chars[0], 'm');
    });

    test('with two commands with two default parameters', () {
      final eng = Engine();
      final cp = MockProvider(); // MockCsiProvider();

      const input = '\x1b\x5b;m\x1b\x5b1;x';
      stringAdvance(eng, cp, input);

      expect(cp.params.length, 2);
      expect(cp.params[0], <int>[0, 0]); // default parameters values
      expect(cp.params[1], <int>[1, 0]); // default parameters values
      expect(cp.chars.length, 2);
      expect(cp.chars[0], 'm');
      expect(cp.chars[1], 'x');
    });

    test('csi with trailing semicolon', () {
      final eng = Engine();
      final cp = MockProvider(); // MockCsiProvider();

      const input = '\x1b\x5b123;m';
      stringAdvance(eng, cp, input);

      expect(cp.params.length, 1);
      expect(cp.params[0], <int>[123, 0]); // default parameters values
      expect(cp.chars.length, 1);
      expect(cp.chars[0], 'm');
    });

    test('csi max parameters', () {
      final eng = Engine();
      final cp = MockProvider(); // MockCsiProvider();

      const input = '\x1b\x5b1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30m';
      stringAdvance(eng, cp, input);

      expect(cp.params.length, 1);
      expect(cp.params[0], <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        29,
        30,
      ]); //
      expect(cp.chars.length, 1);
      expect(cp.chars[0], 'm');
    });

    test(
      'csi bracketed paste',
      () {
        final eng = Engine();
        final cp = MockProvider(); // MockCsiProvider();

        const startPasteSeq = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7E]; // ESC [ 2 0 0 ~
        const endPasteSeq = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7E]; // ESC [ 2 0 1 ~

        listAdvance(eng, cp, [...startPasteSeq, 0x61, 0xc3, 0xb1, 0x63, ...endPasteSeq]);
        expect(cp.chars.length, 4);
        expect(cp.chars[0], 'a');
        expect(cp.chars[1], 'ñ');
        expect(cp.chars[2], 'c');
        expect(cp.params.length, 1);
        expect(cp.params[0], <int>[200, 201]);
      },
    );

    test('parse utf8 characters', () {
      final eng = Engine();
      final cp = MockProvider(); // MockCharProvider();

      stringAdvance(eng, cp, 'a');
      expect(cp.chars.length, 1);
      expect(cp.chars[0], 'a');

      listAdvance(eng, cp, [0xc3, 0xb1]);
      expect(cp.chars.length, 2);
      expect(cp.chars[1], 'ñ');

      listAdvance(eng, cp, [0xe2, 0x81, 0xa1]);
      expect(cp.chars.length, 3);
      expect(cp.chars[2], '\u2061');

      listAdvance(eng, cp, [0xf0, 0x90, 0x8c, 0xbc]);
      expect(cp.chars.length, 4);
      expect(cp.chars[3], '𐌼');
    });
  });
}
