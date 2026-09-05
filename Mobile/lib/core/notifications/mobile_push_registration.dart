import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../storage/secure_session_store.dart';
import '../../features/collaboration/data/collaboration_repositories.dart';

final class MobilePushToken {
  const MobilePushToken({
    required this.platform,
    required this.provider,
    required this.value,
  });

  factory MobilePushToken.fromMap(Map<Object?, Object?> value) =>
      MobilePushToken(
        platform: value['platform']?.toString().trim() ?? '',
        provider: value['provider']?.toString().trim() ?? '',
        value: value['token']?.toString().trim() ?? '',
      );

  final String platform;
  final String provider;
  final String value;

  bool get isValid =>
      platform.isNotEmpty && provider.isNotEmpty && value.isNotEmpty;

  String get fingerprint => '$platform\u0000$provider\u0000$value';
}

abstract interface class MobilePushTokenSource {
  Future<MobilePushToken?> currentToken();
  Future<String?> initialTargetRoute();
  Stream<MobilePushToken> get tokenChanges;
  Stream<String> get notificationClicks;
}

final class NativeMobilePushTokenSource implements MobilePushTokenSource {
  NativeMobilePushTokenSource({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    String? storageNamespace,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('com.hexing.zhilian/push'),
       _eventChannel =
           eventChannel ?? const EventChannel('com.hexing.zhilian/push/events'),
       _storageNamespace = storageNamespace ?? AppEnvironment.storageNamespace;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final String _storageNamespace;
  // This native migration is Android-only. The existing APNs bridge has a
  // separate pending Keychain migration; do not silently disable it here.
  bool get _requiresScopedToken =>
      defaultTargetPlatform == TargetPlatform.android;
  Stream<Object?>? _events;

  Stream<Object?> get _eventStream => _events ??= _eventChannel
      .receiveBroadcastStream({'storageNamespace': _storageNamespace})
      .handleError((_) {});

  @override
  Future<MobilePushToken?> currentToken() async {
    try {
      final value = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'getToken',
        {'storageNamespace': _storageNamespace},
      );
      if (value == null ||
          (_requiresScopedToken &&
              value['storageNamespace'] != _storageNamespace)) {
        return null;
      }
      final token = MobilePushToken.fromMap(value);
      return token.isValid ? token : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> initialTargetRoute() async {
    try {
      final route = await _methodChannel.invokeMethod<String>(
        'getInitialNotification',
      );
      return normalizeMobilePushTargetRoute(route);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<MobilePushToken> get tokenChanges => _eventStream
      .map(_eventMap)
      .where(
        (event) =>
            event?['type'] == 'token' &&
            (!_requiresScopedToken ||
                event?['storageNamespace'] == _storageNamespace),
      )
      .map((event) => MobilePushToken.fromMap(event!))
      .where((token) => token.isValid);

  @override
  Stream<String> get notificationClicks => _eventStream
      .map(_eventMap)
      .where((event) => event?['type'] == 'notification')
      .map((event) => normalizeMobilePushTargetRoute(event!['targetRoute']))
      .where((route) => route != null)
      .cast<String>();

  static Map<Object?, Object?>? _eventMap(Object? value) =>
      value is Map ? value.cast<Object?, Object?>() : null;
}

final class DemoMobilePushTokenSource implements MobilePushTokenSource {
  const DemoMobilePushTokenSource();

  @override
  Future<MobilePushToken?> currentToken() async => const MobilePushToken(
    platform: 'android',
    provider: 'fcm',
    value: 'demo-mobile-push-token',
  );

  @override
  Future<String?> initialTargetRoute() async => null;

  @override
  Stream<MobilePushToken> get tokenChanges => const Stream.empty();

  @override
  Stream<String> get notificationClicks => const Stream.empty();
}

String? normalizeMobilePushTargetRoute(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  if (raw == '/contacts?mode=requests') return raw;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path != raw) {
    return null;
  }
  if (const {
    '/messages',
    '/todos',
    '/notifications',
    '/contacts',
  }.contains(uri.path)) {
    return uri.path;
  }
  if (RegExp(
    r'^/chat/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(uri.path)) {
    return uri.path;
  }
  if (RegExp(
    r'^/approval/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(uri.path)) {
    return uri.path;
  }
  return null;
}

final mobilePushTokenSourceProvider = Provider<MobilePushTokenSource>(
  (ref) => AppEnvironment.demoMode
      ? const DemoMobilePushTokenSource()
      : NativeMobilePushTokenSource(),
);

final mobilePushRuntimeTokenProvider = StreamProvider<MobilePushToken?>((
  ref,
) async* {
  final source = ref.read(mobilePushTokenSourceProvider);
  final pendingTokens = StreamController<MobilePushToken?>();
  final subscription = source.tokenChanges.listen(
    pendingTokens.add,
    onError: pendingTokens.addError,
  );
  try {
    yield await source.currentToken();
    yield* pendingTokens.stream;
  } finally {
    await subscription.cancel();
    await pendingTokens.close();
  }
});

final mobilePushRegistrationProvider = Provider<MobilePushRegistration>((ref) {
  final repository = ref.read(imRepositoryProvider);
  final store = ref.read(secureSessionStoreProvider);
  final registration = MobilePushRegistration.withCallbacks(
    ref.read(mobilePushTokenSourceProvider),
    repository.registerPushDevice,
    repository.unregisterPushDevice,
    saveSecureToken: store.savePushToken,
    clearSecureToken: store.clearPushToken,
    sessionStore: store,
  );
  ref.onDispose(registration.stop);
  return registration;
});

typedef RegisterMobilePushToken = Future<void> Function({
  required String platform,
  required String provider,
  required String token,
  String privacyMode,
  MobileSession? forSession,
});

final class MobilePushRegistration {
  MobilePushRegistration(
    MobilePushTokenSource tokenSource, {
    required RegisterMobilePushToken register,
    required Future<void> Function({MobileSession? forSession}) unregister,
    Future<void> Function(String value)? saveSecureToken,
    Future<void> Function()? clearSecureToken,
    SecureSessionStore? sessionStore,
  }) : this.withCallbacks(
         tokenSource,
         register,
         unregister,
         saveSecureToken: saveSecureToken,
         clearSecureToken: clearSecureToken,
         sessionStore: sessionStore,
       );

  MobilePushRegistration.withCallbacks(
    this._tokenSource,
    this._register,
    this._unregister, {
    this.saveSecureToken,
    this.clearSecureToken,
    this.sessionStore,
  });

  final MobilePushTokenSource _tokenSource;
  final RegisterMobilePushToken _register;
  final Future<void> Function({MobileSession? forSession}) _unregister;
  final Future<void> Function(String value)? saveSecureToken;
  final Future<void> Function()? clearSecureToken;
  final SecureSessionStore? sessionStore;
  StreamSubscription<MobilePushToken>? _tokenSubscription;
  StreamSubscription<String>? _notificationSubscription;
  String _lastRegisteredFingerprint = '';
  bool _started = false;
  bool _enabled = true;
  int _generation = 0;
  int _tokenEventRevision = 0;
  String _privacyMode = 'summary';
  MobileSession? _lastRegisteredSession;
  Future<void> _operations = Future<void>.value();

  bool _active(int generation) => _enabled && generation == _generation;

  Future<bool> _current(int generation, MobileSession? expected) async {
    if (!_active(generation)) return false;
    if (sessionStore == null) return true;
    final current = await sessionStore!.readSession();
    return _active(generation) &&
        expected != null &&
        current != null &&
        current.isSameSession(expected);
  }

  Future<void> start({
    required FutureOr<void> Function(String route) onOpenRoute,
  }) async {
    if (_started) return;
    _started = true;
    _enabled = true;
    final generation = _generation;
    _tokenSubscription = _tokenSource.tokenChanges.listen((token) {
      _tokenEventRevision += 1;
      _synchronize(token: token, generation: generation).ignore();
    }, onError: (Object _) {});
    _notificationSubscription = _tokenSource.notificationClicks.listen((route) {
      if (_active(generation)) {
        Future<void>.sync(() => onOpenRoute(route)).ignore();
      }
    }, onError: (Object _) {});
    await synchronize();
    if (!_active(generation)) return;
    final initialRoute = await _tokenSource.initialTargetRoute();
    if (_active(generation) && initialRoute != null) {
      await onOpenRoute(initialRoute);
    }
  }

  Future<bool> synchronize({String? privacyMode}) {
    if (!_enabled) return Future<bool>.value(false);
    if (privacyMode != null) _privacyMode = privacyMode;
    return _synchronize(generation: _generation);
  }

  Future<bool> _synchronize({
    MobilePushToken? token,
    required int generation,
  }) async {
    if (!_active(generation)) return false;
    final tokenEventRevision = _tokenEventRevision;
    final session = await sessionStore?.readSession();
    if (!await _current(generation, session)) return false;
    final currentToken = token ?? await _tokenSource.currentToken();
    if (token == null && tokenEventRevision != _tokenEventRevision) {
      return false;
    }
    if (!await _current(generation, session)) return false;
    final privacyMode = _privacyMode;
    final operation = _operations.then(
      (_) => _registerToken(
        currentToken,
        privacyMode: privacyMode,
        generation: generation,
        session: session,
      ),
    );
    _operations = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<bool> _registerToken(
    MobilePushToken? token, {
    required String privacyMode,
    required int generation,
    required MobileSession? session,
  }) async {
    if (token == null || !token.isValid) return false;
    if (!await _current(generation, session)) return false;
    final registrationFingerprint = '${token.fingerprint}\u0000$privacyMode';
    if (_lastRegisteredFingerprint == registrationFingerprint &&
        (sessionStore == null ||
            _lastRegisteredSession?.isSameSession(session!) == true)) {
      return true;
    }
    await _register(
      platform: token.platform,
      provider: token.provider,
      token: token.value,
      privacyMode: privacyMode,
      forSession: session,
    );
    if (!await _current(generation, session)) return false;
    if (sessionStore != null && session != null) {
      await sessionStore!.withCurrentSession(session, () async {
        if (_active(generation)) await saveSecureToken?.call(token.fingerprint);
      });
    } else {
      await saveSecureToken?.call(token.fingerprint);
    }
    if (!await _current(generation, session)) return false;
    _lastRegisteredFingerprint = registrationFingerprint;
    _lastRegisteredSession = session;
    return true;
  }

  Future<void> unregister() async {
    final generation = _generation;
    final session = await sessionStore?.readSession();
    if (!await _current(generation, session)) return;
    stop();
    try {
      await _unregister(forSession: session);
    } finally {
      if (sessionStore != null && session != null) {
        try {
          await sessionStore!.withCurrentSession(session, () async {
            await clearSecureToken?.call();
          });
        } on SessionChangedException {
          // A late logout response cannot erase a new account's token.
        }
      } else {
        await clearSecureToken?.call();
      }
    }
  }

  void stop() {
    _generation += 1;
    _enabled = false;
    _started = false;
    _lastRegisteredFingerprint = '';
    _lastRegisteredSession = null;
    _privacyMode = 'summary';
    // Old requests retain their session, but cannot block a new login runtime.
    _operations = Future<void>.value();
    unawaited(_tokenSubscription?.cancel());
    unawaited(_notificationSubscription?.cancel());
    _tokenSubscription = null;
    _notificationSubscription = null;
  }
}
