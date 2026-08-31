import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
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
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('com.hexing.zhilian/push'),
       _eventChannel =
           eventChannel ?? const EventChannel('com.hexing.zhilian/push/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<Object?>? _events;

  Stream<Object?> get _eventStream =>
      _events ??= _eventChannel.receiveBroadcastStream().handleError((_) {});

  @override
  Future<MobilePushToken?> currentToken() async {
    try {
      final value = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'getToken',
      );
      if (value == null) return null;
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
      .where((event) => event?['type'] == 'token')
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
  final registration = MobilePushRegistration.withCallbacks(
    ref.read(mobilePushTokenSourceProvider),
    repository.registerPushDevice,
    repository.unregisterPushDevice,
  );
  ref.onDispose(registration.stop);
  return registration;
});

typedef RegisterMobilePushToken = Future<void> Function({
  required String platform,
  required String provider,
  required String token,
  String privacyMode,
});

final class MobilePushRegistration {
  MobilePushRegistration(
    MobilePushTokenSource tokenSource, {
    required RegisterMobilePushToken register,
    required Future<void> Function() unregister,
  }) : this.withCallbacks(tokenSource, register, unregister);

  MobilePushRegistration.withCallbacks(
    this._tokenSource,
    this._register,
    this._unregister,
  );

  final MobilePushTokenSource _tokenSource;
  final RegisterMobilePushToken _register;
  final Future<void> Function() _unregister;
  StreamSubscription<MobilePushToken>? _tokenSubscription;
  StreamSubscription<String>? _notificationSubscription;
  String _lastRegisteredFingerprint = '';
  bool _started = false;

  Future<void> start({required void Function(String route) onOpenRoute}) async {
    if (_started) return;
    _started = true;
    _tokenSubscription = _tokenSource.tokenChanges.listen(
      (token) => unawaited(_registerToken(token)),
    );
    _notificationSubscription = _tokenSource.notificationClicks.listen(
      onOpenRoute,
    );
    await synchronize();
    final initialRoute = await _tokenSource.initialTargetRoute();
    if (initialRoute != null) onOpenRoute(initialRoute);
  }

  Future<bool> synchronize({String privacyMode = 'summary'}) async {
    final token = await _tokenSource.currentToken();
    return _registerToken(token, privacyMode: privacyMode);
  }

  Future<bool> _registerToken(
    MobilePushToken? token, {
    String privacyMode = 'summary',
  }) async {
    if (token == null || !token.isValid) return false;
    final registrationFingerprint = '${token.fingerprint}\u0000$privacyMode';
    if (_lastRegisteredFingerprint == registrationFingerprint) return true;
    await _register(
      platform: token.platform,
      provider: token.provider,
      token: token.value,
      privacyMode: privacyMode,
    );
    _lastRegisteredFingerprint = registrationFingerprint;
    return true;
  }

  Future<void> unregister() async {
    _lastRegisteredFingerprint = '';
    await _unregister();
  }

  void stop() {
    _started = false;
    unawaited(_tokenSubscription?.cancel());
    unawaited(_notificationSubscription?.cancel());
    _tokenSubscription = null;
    _notificationSubscription = null;
  }
}
