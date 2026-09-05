import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real repository + SQLite transaction; pause the first encryption write,
/// not a fake HTTP send. No sync loop is started and no network is needed.
class ChatComposerFixture {
  ChatComposerFixture(this.sessions, this.store, this.cipher)
    : repository = ImRepository(CollaborationClient(sessions), sessions, store);

  final SecureSessionStore sessions;
  final ImLocalStore store;
  final ComposerWriteGate cipher;
  final ImRepository repository;

  static Future<ChatComposerFixture> create() async {
    sqfliteFfiInit();
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    final sessions = SecureSessionStore();
    await sessions.saveSession(
      const MobileSession(
        accessToken: 'local-composer-fixture',
        deviceId: 'fixture-device',
        userId: 'me',
        displayName: '测试',
        username: 'fixture',
        policySignatureKey: '',
        imApiUrl: 'http://127.0.0.1:1',
        oaApiUrl: '',
      ),
    );
    final cipher = ComposerWriteGate();
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
      cipher: cipher,
    );
    await store.readMessages('me', 'ops');
    return ChatComposerFixture(sessions, store, cipher);
  }
}

class ComposerWriteGate implements ImCacheCipher {
  Completer<void>? _release;
  Completer<void> entered = Completer<void>();
  bool fail = false;

  void hold({bool failure = false}) {
    entered = Completer<void>();
    _release = Completer<void>();
    fail = failure;
  }

  void release() {
    if (_release?.isCompleted == false) _release!.complete();
  }

  @override
  bool get isEnabled => false;
  @override
  bool isProtected(String value) => false;
  @override
  Future<String> reveal(String accountId, String value) async => value;
  @override
  Future<String> protect(String accountId, String value) async {
    final gate = _release;
    if (gate != null) {
      if (!entered.isCompleted) entered.complete();
      await gate.future;
      _release = null;
      if (fail) throw StateError('fixture local storage unavailable');
    }
    return value;
  }
}
