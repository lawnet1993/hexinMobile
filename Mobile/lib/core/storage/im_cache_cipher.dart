import 'dart:convert';

import 'package:cryptography/cryptography.dart';

abstract interface class ImCacheCipher {
  bool get isEnabled;
  bool isProtected(String value);
  Future<String> protect(String accountId, String value);
  Future<String> reveal(String accountId, String value);
}

final class PlainImCacheCipher implements ImCacheCipher {
  const PlainImCacheCipher();

  @override
  bool get isEnabled => false;

  @override
  bool isProtected(String value) => false;

  @override
  Future<String> protect(String accountId, String value) async => value;

  @override
  Future<String> reveal(String accountId, String value) async => value;
}

final class AesGcmImCacheCipher implements ImCacheCipher {
  AesGcmImCacheCipher(this._keyLoader);

  static const _prefix = 'enc:v1:';
  final Future<List<int>> Function(String accountId) _keyLoader;
  final _algorithm = AesGcm.with256bits();
  final Map<String, Future<SecretKey>> _keys = {};

  @override
  bool get isEnabled => true;

  @override
  bool isProtected(String value) => value.startsWith(_prefix);

  @override
  Future<String> protect(String accountId, String value) async {
    if (value.isEmpty || isProtected(value)) return value;
    final box = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: await _key(accountId),
      aad: utf8.encode(accountId),
    );
    return '$_prefix${base64UrlEncode(box.concatenation())}';
  }

  @override
  Future<String> reveal(String accountId, String value) async {
    if (value.isEmpty || !isProtected(value)) return value;
    try {
      final bytes = base64Url.decode(value.substring(_prefix.length));
      final box = SecretBox.fromConcatenation(
        bytes,
        nonceLength: _algorithm.nonceLength,
        macLength: _algorithm.macAlgorithm.macLength,
      );
      final clearText = await _algorithm.decrypt(
        box,
        secretKey: await _key(accountId),
        aad: utf8.encode(accountId),
      );
      return utf8.decode(clearText);
    } on SecretBoxAuthenticationError {
      throw StateError('IM cache authentication failed.');
    } on FormatException {
      throw StateError('IM cache payload is malformed.');
    } on ArgumentError {
      throw StateError('IM cache payload is malformed.');
    }
  }

  Future<SecretKey> _key(String accountId) =>
      _keys.putIfAbsent(accountId, () async {
        final bytes = await _keyLoader(accountId);
        if (bytes.length != 32) {
          throw StateError('IM cache key must contain 32 bytes.');
        }
        return SecretKey(bytes);
      });
}
