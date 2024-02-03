// ignore_for_file: public_member_api_docs

import 'dart:convert';

import './extensions/int_extension.dart';
import './provider.dart';

const _maxParameters = 30;
const _defaultParameterValue = 0;
const _maxUtf8CodePoints = 4;

/// A parser engine state.
///
/// All these variant names come from the
/// [A parser for DEC’s ANSI-compatible video terminals](https://vt100.net/emu/dec_ansi_parser)
/// description.
enum State {
  /// Initial state.
  ground,

  /// Escape sequence started.
  ///
  /// `Esc` received with a flag that there's more data available.
  escape,

  /// Escape sequence and we're collecting intermediates.
  ///
  /// # Notes
  ///
  /// This implementation doesn't collect intermediates. It just handles the state
  /// to distinguish between (im)proper sequences.
  escapeIntermediate,

  /// CSI sequence started.
  ///
  /// `Esc` followed by the `[` received.
  csiEntry,

  /// CSI sequence should be consumed, but not dispatched.
  csiIgnore,

  /// CSI sequence and we're collecting parameters.
  csiParameter,

  /// CSI sequence and we're collecting intermediates.
  ///
  /// # Notes
  ///
  /// This implementation doesn't collect intermediates. It just handles the state
  /// to distinguish between (im)proper sequences.
  csiIntermediate,

  /// CSI sequence block
  ///
  /// used for bracketed paste mode for example
  csiBlock,

  /// Possible UTF-8 sequence and we're collecting UTF-8 code points.
  utf8,
}

///
class Engine {
  final parameters = List<int>.filled(_maxParameters, _defaultParameterValue);
  int parametersCount = 0;
  int parameter = _defaultParameterValue;
  int ignoredParametersCount = 0;
  State state = State.ground;
  final utf8Points = List<int>.filled(_maxUtf8CodePoints, 0);
  int utf8PointsCount = 0;
  int utf8PointsExpectedCount = 0;
  bool inCsiBlock = false;

  Engine() {
    parameters.fillRange(0, parameters.length, _defaultParameterValue);
    parametersCount = 0;
    parameter = _defaultParameterValue;
    ignoredParametersCount = 0;
    state = State.ground;
    utf8Points.fillRange(0, utf8Points.length, 0);
    utf8PointsCount = 0;
    utf8PointsExpectedCount = 0;
  }

  void setState(State newState) {
    if (newState == State.ground) {
      parametersCount = 0;
      parameter = _defaultParameterValue;
      ignoredParametersCount = 0;
      utf8PointsCount = 0;
      utf8PointsExpectedCount = 0;
    }
    state = newState;
  }

  void storeParameter() {
    if (parametersCount < _maxParameters) {
      parameters[parametersCount] = parameter;
      parametersCount++;
    } else {
      ignoredParametersCount++;
    }
    parameter = _defaultParameterValue;
  }

  bool handlePossibleEsc(Provider provider, int byte, {bool more = false}) {
    if (byte != 0x1b) {
      return false;
    }

    switch ((state, more)) {
      // More input means possible Esc sequence, just switch state and wait
      case (State.ground, true):
        setState(State.escape);
      // No more input means Esc key, dispatch it
      case (State.ground, false):
        provider.provideChar('\x1b');
      // More input means possible Esc sequence, dispatch the previous Esc char
      case (State.escape, true):
        provider.provideChar('\x1b');
      // No more input means Esc key, dispatch the previous & current Esc char
      case (State.escape, false):
        provider.provideChar('\x1b');
        provider.provideChar('\x1b');
        setState(State.ground);

      // Discard any state
      // More input means possible Esc sequence
      case (_, true):
        setState(State.escape);
      // Discard any state
      // No more input means Esc key, dispatch it
      case (_, false):
        provider.provideChar('\x1b');
        setState(State.ground);
    }

    return true;
  }

  bool handlePossibleUtf8CodePoints(Provider provider, int byte) {
    if (byte & 0x80 == 0) {
      provider.provideChar(String.fromCharCode(byte));
      return true;
    } else if (byte & 0xe0 == 0xc0) {
      utf8PointsCount = 1;
      utf8Points[0] = byte;
      utf8PointsExpectedCount = 2;
      setState(State.utf8);
      return true;
    } else if (byte & 0xf0 == 0xe0) {
      utf8PointsCount = 1;
      utf8Points[0] = byte;
      utf8PointsExpectedCount = 3;
      setState(State.utf8);
      return true;
    } else if (byte & 0xf8 == 0xf0) {
      utf8PointsCount = 1;
      utf8Points[0] = byte;
      utf8PointsExpectedCount = 4;
      setState(State.utf8);
      return true;
    } else {
      return false;
    }
  }

  void advanceGroundState(Provider provider, int byte) {
    if (handlePossibleUtf8CodePoints(provider, byte)) return;

    return switch (byte) {
      0x1b => throw Exception('Unexpected Esc byte in ground state'),
      // Execute
      (>= 0x00 && <= 0x17) || 0x19 || (>= 0x1C && <= 0x1F) => provider.provideChar(String.fromCharCode(byte)),

      // Print
      >= 0x20 && <= 0x7F => provider.provideChar(String.fromCharCode(byte)),
      _ => {},
    };
  }

  void advanceEscapeState(Provider provider, int byte) {
    switch (byte) {
      case 0x1b:
        throw Exception('Unexpected Esc byte in Advance State');
      // Intermediate bytes to collect
      case >= 0x20 && <= 0x2F:
        setState(State.escapeIntermediate);
      // Escape followed by '[' (0x5B)
      //   -> CSI sequence start
      case 0x5b:
        setState(State.csiEntry);

      // Escape sequence final character
      case (>= 0x30 && <= 0x4F) || (>= 0x51 && <= 0x57) || 0x59 || 0x5A || 0x5C || (>= 0x60 && <= 0x7E):
        provider.provideESCSequence(String.fromCharCode(byte));
        setState(State.ground);

      // Execute
      case (>= 0x00 && <= 0x17) || 0x19 || (>= 0x1C && <= 0x1F):
        provider.provideChar(String.fromCharCode(byte));

      // Does it mean we should ignore the whole sequence?
      // Ignore
      case 0x7F:
        {}

      // Other bytes are considered as invalid -> cancel whatever we have
      default:
        setState(State.ground);
    }
  }

  void advanceEscapeIntermediateState(Provider provider, int byte) {
    switch (byte) {
      case 0x1b:
        throw Exception('Unexpected Esc byte in ESC Intermediate');

      // Intermediate bytes to collect
      case >= 0x20 && <= 0x2F:
        {}

      // Escape followed by '[' (0x5B)
      //   -> CSI sequence start
      case 0x5B:
        setState(State.csiEntry);

      // Escape sequence final character
      case (>= 0x30 && <= 0x5A) || (>= 0x5C && <= 0x7E):
        provider.provideESCSequence(String.fromCharCode(byte));
        setState(State.ground);

      // Execute
      case (>= 0x00 && <= 0x17) || 0x19 || (>= 0x1C && <= 0x1F):
        provider.provideChar(String.fromCharCode(byte));

      // Does it mean we should ignore the whole sequence?
      // Ignore
      case 0x7F:
        {}

      // Other bytes are considered as invalid -> cancel whatever we have
      default:
        setState(State.ground);
    }
  }

  void advanceCsiEntryState(Provider provider, int byte) {
    switch (byte) {
      case 0x1b:
        throw Exception('Unexpected Esc byte in CSI Entry state');

      // Semicolon = parameter delimiter
      case 0x3B:
        {
          storeParameter();
          setState(State.csiParameter);
        }

      // '0' ..= '9' = parameter value
      case >= 0x30 && <= 0x39:
        {
          parameter = byte - 0x30;
          setState(State.csiParameter);
        }

      case 0x3A:
        setState(State.csiIgnore);

      // CSI sequence final character
      //   -> dispatch CSI sequence
      case >= 0x40 && <= 0x7E:
        provider.provideCSISequence(
          parameters.sublist(0, parametersCount),
          ignoredParametersCount,
          String.fromCharCode(byte),
        );

        setState(State.ground);

      // Execute
      case (>= 0x00 && <= 0x17) || 0x19 || (>= 0x1C && <= 0x1F):
        provider.provideChar(String.fromCharCode(byte));

      // Does it mean we should ignore the whole sequence?
      // Ignore
      case 0x7F:
        {}

      // Collect rest as parameters
      default:
        parameter = byte;
        storeParameter();
    }
  }

  void advanceCsiIgnoreState(Provider provider, int byte) {
    switch (byte) {
      case 0x1b:
        throw Exception('Unexpected Esc byte in CSI Ignore');

      // Execute
      case (>= 0x00 && <= 0x17) || 0x19 || (>= 0x1C && <= 0x1F):
        provider.provideChar(String.fromCharCode(byte));

      // Does it mean we should ignore the whole sequence?
      // Ignore
      case (>= 0x20 && <= 0x3F) || 0x7F:
        {}

      case (>= 0x40 && <= 0x7E):
        setState(State.ground);

      // Other bytes are considered as invalid -> cancel whatever we have
      default:
        setState(State.ground);
    }
  }

  void advanceCsiParameterState(Provider provider, int byte) {
    switch (byte) {
      case 0x1b:
        throw Exception('Unexpected Esc byte in CSI Param');

      // '0' ..= '9' = parameter value
      case (>= 0x30 && <= 0x39):
        {
          parameter = parameter.saturatingMul(10);
          parameter = parameter.saturatingAdd(byte - 0x30);
        }

      // Semicolon = parameter delimiter
      case 0x3B:
        storeParameter();

      case 0x7E:
        storeParameter();
        if (inCsiBlock) {
          provider.provideCSISequence(
            parameters.sublist(0, parametersCount),
            ignoredParametersCount,
            '',
          );
          inCsiBlock = false;
          setState(State.ground);
        } else {
          inCsiBlock = true;
          setState(State.csiBlock);
        }

      // CSI sequence final character
      //   -> dispatch CSI sequence
      case (>= 0x40 && <= 0x7D):
        storeParameter();
        provider.provideCSISequence(
          parameters.sublist(0, parametersCount),
          ignoredParametersCount,
          String.fromCharCode(byte),
        );

        setState(State.ground);

      // Intermediates to collect
      case (>= 0x20 && <= 0x2F):
        storeParameter();
        setState(State.csiIntermediate);

      // Ignore
      case 0x3A || (>= 0x3C && <= 0x3F):
        setState(State.csiIgnore);

      // Execute
      case (>= 0x00 && <= 0x17) || 0x19 || (>= 0x1C && <= 0x1F):
        provider.provideChar(String.fromCharCode(byte));

      // Does it mean we should ignore the whole sequence?
      // Ignore
      case 0x7F:
        {}

      // Other bytes are considered as invalid -> cancel whatever we have
      default:
        setState(State.ground);
    }
  }

  void advanceCsiBlockState(Provider provider, int byte) {
    switch (byte) {
      case 0x1b:
        provider.provideCSISequence(
          parameters.sublist(0, parametersCount),
          ignoredParametersCount,
          String.fromCharCode(byte),
        );

        setState(State.escape);

      // Other bytes are considered as valid
      default:
        provider.provideChar(String.fromCharCode(byte));
    }
  }

  void advanceCsiIntermediateState(Provider provider, int byte) {
    switch (byte) {
      case 0x1b:
        throw Exception('Unexpected Esc byte in CSI intermediate');

      // Intermediates to collect
      case (>= 0x20 && <= 0x2F):
        {}

      // CSI sequence final character
      //   -> dispatch CSI sequence
      case (>= 0x40 && <= 0x7E):
        provider.provideCSISequence(
          parameters.sublist(0, parametersCount),
          ignoredParametersCount,
          String.fromCharCode(byte),
        );

        setState(State.ground);
      // Execute
      case (>= 0x00 && <= 0x17) || 0x19 || (>= 0x1C && <= 0x1F):
        provider.provideChar(String.fromCharCode(byte));

      // Does it mean we should ignore the whole sequence?
      // Ignore
      case 0x7F:
        {}

      // Other bytes are considered as invalid -> cancel whatever we have
      default:
        setState(State.ground);
    }
  }

  void advanceUtf8State(Provider provider, int byte) {
    if (byte & 0xC0 != 0x80) {
      setState(State.ground);
      return;
    }
    utf8Points[utf8PointsCount] = byte;
    utf8PointsCount++;

    if (utf8PointsCount == utf8PointsExpectedCount) {
      final data = utf8.decode(utf8Points.sublist(0, utf8PointsCount));
      provider.provideChar(data);
      setState(State.ground);
    }
  }

  void advance(Provider provider, int byte, {bool more = false}) {
    // print('advance: $state, ${byte.toRadixString(16)}, $more');
    if (handlePossibleEsc(provider, byte, more: more)) {
      return;
    }

    return switch (state) {
      State.ground => advanceGroundState(provider, byte),
      State.escape => advanceEscapeState(provider, byte),
      State.escapeIntermediate => advanceEscapeIntermediateState(provider, byte),
      State.csiEntry => advanceCsiEntryState(provider, byte),
      State.csiIgnore => advanceCsiIgnoreState(provider, byte),
      State.csiParameter => advanceCsiParameterState(provider, byte),
      State.csiIntermediate => advanceCsiIntermediateState(provider, byte),
      State.csiBlock => advanceCsiBlockState(provider, byte),
      State.utf8 => advanceUtf8State(provider, byte),
    };
  }
}
