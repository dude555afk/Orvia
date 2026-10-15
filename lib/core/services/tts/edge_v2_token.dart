import 'dart:convert';
import 'dart:typed_data';

/// Microsoft Read Aloud v2 handshake token.
/// Adapted from MIT-licensed msedge-tts (hs-CN/msedge-tts), drm.rs.
/// Upstream reference: https://github.com/hs-CN/msedge-tts
class EdgeV2Token {
  EdgeV2Token._();
  static const clientKey = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const protocolVersion = '2-155.0.4283.45';
  static const _mask = 0xffffffff;
  static const _initial = <int>[
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
  ];
  static const _saltState = <int>[
    0xFD9FBEA2,
    0x91243CE7,
    0xBE499094,
    0xCD2E1E0A,
    0x6C006F49,
    0x04BD35AB,
    0xFEB0A7E4,
    0x03EFFBD2,
  ];
  static const _schedule = <int>[
    0xEB24BF9E,
    0x1558691F,
    0xA0C09EE2,
    0x0CFA32BA,
    0xA622EE8C,
    0xD1DD9491,
    0xC0DD25A0,
    0xF9E70AB6,
    0xF0C31573,
    0x7058CE4E,
    0x7188E606,
    0x00E5AB33,
    0xD258B060,
    0x72766564,
  ];
  static const _roundKeys = <int>[
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
  ];
  static const _csConstants = <List<int>>[
    [0xE82E91B1, 0xB32700D0],
    [0x44DE24C6, 0x88DFF51D],
    [0x3BEB65BC, 0x29514038],
    [0xC89C5933, 0xB328CBDF],
    [0x8D1EC211, 0xD405B4D5],
    [0x314EF5D5, 0x26E55F3C],
    [0xE92491B1, 0x607801C6],
    [0xF0A5B9D5, 0x82B2C1FB],
    [0x06064CF3, 0xFA51A3DA],
    [0xDA79FA60, 0x207CC464],
    [0xBED20560, 0x3C3C74F3],
    [0x89F9C9F8, 0xD2D14B61],
    [0x35FA38C6, 0xBB04A2C1],
    [0xCB49E3C6, 0xC5626167],
  ];
  static int _u(int v) => v & _mask;
  static int _rol(int v, int n) => _u((v << n) | (v >> (32 - n)));
  static int _ror(int v, int n) => _u((v >> n) | (v << (32 - n)));
  static int _small0(int v) => _ror(v, 7) ^ _ror(v, 18) ^ (v >> 3);
  static int _small1(int v) => _ror(v, 17) ^ _ror(v, 19) ^ (v >> 10);

  static void _extend(List<int> words, int start) {
    for (var i = start; i < 64; i++) {
      words.add(
        _u(
          _small1(words[i - 2]) +
              words[i - 7] +
              _small0(words[i - 15]) +
              words[i - 16],
        ),
      );
    }
  }

  static List<int> _shaRounds(List<int> initial, List<int> words, int first) {
    var a = initial[0], b = initial[1], c = initial[2], d = initial[3];
    var e = initial[4], f = initial[5], g = initial[6], h = initial[7];
    for (var i = first; i < 64; i++) {
      final key = first == 14 && i == 14 ? 0xC9DC06A7 : _roundKeys[i];
      final temp1 = _u(
        h +
            (_ror(e, 6) ^ _ror(e, 11) ^ _ror(e, 25)) +
            (g ^ (e & (f ^ g))) +
            key +
            words[i],
      );
      final temp2 = _u(
        (_ror(a, 2) ^ _ror(a, 13) ^ _ror(a, 22)) + ((a & b) | (c & (a | b))),
      );
      h = g;
      g = f;
      f = e;
      e = _u(d + temp1);
      d = c;
      c = b;
      b = a;
      a = _u(temp1 + temp2);
    }
    return [a, b, c, d, e, f, g, h];
  }

  static List<int> _saltInitial(List<int> firstSeven) {
    final w = List<int>.filled(14, 0);
    w.add((firstSeven[0] << 16) | (firstSeven[1] << 8) | firstSeven[2]);
    w.add(
      (firstSeven[3] << 24) |
          (firstSeven[4] << 16) |
          (firstSeven[5] << 8) |
          firstSeven[6],
    );
    for (var i = 16; i < 30; i++) {
      var value = _schedule[i - 16];
      if (i - 2 >= 14) {
        final sigma = _small1(w[i - 2]);
        value += i == 16 ? sigma ^ 0x000B92C0 : sigma;
      }
      if (i - 7 >= 14) value += w[i - 7];
      if (i - 15 >= 14) {
        final sigma = _small0(w[i - 15]);
        value += i == 29 ? sigma ^ 0x059C0B80 : sigma;
      }
      w.add(_u(value));
    }
    w.add(
      _u(
        _small1(w[28]) +
            w[23] +
            _small0(w[15]) +
            w[14] +
            0xC9DC06A7 -
            _roundKeys[14],
      ),
    );
    _extend(w, 31);
    final next = _shaRounds(_saltState, w, 14);
    return List<int>.generate(8, (i) => _u(_initial[i] + next[i]));
  }

  static Uint8List _saltHash(List<int> input) {
    var state = _saltInitial(input.sublist(0, 7));
    final length = 57 + input.length;
    final padded = <int>[...input.skip(7), 0x80];
    while ((padded.length + 8) % 64 != 0) {
      padded.add(0);
    }
    final bits = length * 8;
    for (var i = 7; i >= 0; i--) {
      padded.add((bits >> (i * 8)) & 255);
    }
    for (var o = 0; o < padded.length; o += 64) {
      final w = <int>[];
      for (var i = 0; i < 64; i += 4) {
        w.add(
          (padded[o + i] << 24) |
              (padded[o + i + 1] << 16) |
              (padded[o + i + 2] << 8) |
              padded[o + i + 3],
        );
      }
      _extend(w, 16);
      final next = _shaRounds(state, w, 0);
      state = List<int>.generate(8, (i) => _u(state[i] + next[i]));
    }
    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 4; j++) {
        out[i * 4 + j] = (state[i] >> (24 - 8 * j)) & 255;
      }
    }
    return out;
  }

  static int _little(List<int> data, int i) =>
      data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24);

  static Uint8List _cs64(List<int> input, List<int> hash) {
    final a = _little(hash, 0) | 1, b = _little(hash, 4) | 1;
    final factors = [_u(a * 0x82893933), _u(b * 0x82893933)];
    final terms = <int>[], offsets = <int>[];
    for (var i = 0; i < _csConstants.length; i++) {
      terms.add(_u(_csConstants[i][0] * factors[i % 2]));
      offsets.add(_csConstants[i][1]);
    }
    final padded = <int>[0, ...input];
    while (padded.length % 4 != 0) {
      padded.add(0);
    }
    final words = <int>[];
    for (var i = 0; i < padded.length; i += 4) {
      words.add(_little(padded, i));
    }
    if (words.length.isOdd) {
      words.add(0);
    }
    for (var i = 0; i < words.length; i++) {
      var term = _u(words[i] * (i.isEven ? a : b));
      var offset = _u(
        _rol(words[i], 16) * (i.isEven ? 0xEF0569FB : 0xC31713DB),
      );
      if (i == 0) {
        term = _u(term + 0xF2F90B1A * factors[0]);
        offset = _u(offset + 0x0B1A0000);
      }
      terms.add(term);
      offsets.add(offset);
    }
    var swapAcc = 0, swapLast = 0, state = 0, acc = 0;
    for (var i = 0; i < terms.length; i += 2) {
      final x = terms[i], y = terms[i + 1];
      var t = _rol(_u(offsets[i] + x), 16);
      var q = _u(t * 0x76F50F34);
      swapAcc = _u(swapAcc + _u(_rol(q, 16) * 0xC3EFEA97 + q));
      t = _rol(_u(offsets[i + 1] + y), 16);
      q = _u(t * 0x1881CE3C);
      swapLast = _u(_rol(q, 16) * 0x35BD1EC9 + q);
      swapAcc = _u(swapAcc + swapLast);
      state = _u(state * a + x);
      state = _u(_rol(state, 16) * 0xCF98B111);
      state = _u(_rol(state, 16) * 0x87085B9F);
      state = _u(_rol(state, 16) * 0x12CEB96D);
      state = _u(_rol(state, 16) * 0x257E1D83);
      acc = _u(acc + state);
      t = _u(state * b + y);
      t = _u(_rol(t, 16) * 0xA27416F5);
      t = _u(_rol(t, 16) * 0xD38396FF);
      state = _u(_rol(_u(_rol(t, 16) * 0x7C932B89), 16) * 0xBFA49F69);
      acc = _u(acc + state);
    }
    final wordsOut = [_u(swapLast ^ state), _u(swapAcc ^ acc)];
    final out = Uint8List(8);
    for (var i = 0; i < 2; i++) {
      for (var j = 0; j < 4; j++) {
        out[i * 4 + j] = (wordsOut[i] >> (j * 8)) & 255;
      }
    }
    return out;
  }

  static String _hex(Iterable<int> bytes) => bytes
      .map((v) => v.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// Known capture: 2026-10-13T10:40:00Z yields the v2 regression vector.
  static String generate({double? unixSeconds}) {
    var ticks =
        (unixSeconds ?? DateTime.now().millisecondsSinceEpoch / 1000) +
        11644473600;
    ticks -= ticks % 300;
    ticks *= 10000000;
    final bytes = ascii.encode(ticks.toStringAsFixed(0) + clientKey);
    final digest = _saltHash(bytes);
    return _hex(_cs64(bytes, digest)) + '-' + _hex(digest);
  }
}
