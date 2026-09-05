import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/secure_session_store.dart';
import '../../features/auth/application/auth_controller.dart';

final managedSecurityRepositoryProvider = Provider<ManagedSecurityRepository>(
  (ref) => ManagedSecurityRepository(
    ref.read(dioProvider),
    ref.read(secureSessionStoreProvider),
  ),
);

final managedPolicyStatusProvider = FutureProvider<ManagedPolicyStatus>(
  (ref) => ref
      .read(managedSecurityRepositoryProvider)
      .fetchPolicy()
      .timeout(const Duration(seconds: 12)),
  retry: (_, _) => null,
);

final managedTerminalCommandCoordinatorProvider =
    Provider<ManagedTerminalCommandCoordinator>((ref) {
      final coordinator = ManagedTerminalCommandCoordinator(ref);
      ref.onDispose(coordinator.stop);
      return coordinator;
    });

final class ManagedPolicyStatus {
  const ManagedPolicyStatus({
    required this.policyVersion,
    required this.publishedAt,
    required this.enabled,
    required this.signatureVerified,
  });

  final String policyVersion;
  final DateTime? publishedAt;
  final bool enabled;
  final bool signatureVerified;
}

final class ManagedTerminalCommand {
  const ManagedTerminalCommand({
    required this.id,
    required this.commandType,
    required this.durationSeconds,
    required this.expiresAt,
  });

  factory ManagedTerminalCommand.fromJson(Map<String, Object?> json) =>
      ManagedTerminalCommand(
        id: json['id']?.toString() ?? '',
        commandType: _integer(json['commandType']),
        durationSeconds: _integer(json['durationSeconds']),
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      );

  final String id;
  final int commandType;
  final int durationSeconds;
  final DateTime? expiresAt;
}

final class ManagedSecurityRepository {
  const ManagedSecurityRepository(this._dio, this._sessionStore);

  final Dio _dio;
  final SecureSessionStore _sessionStore;

  Future<ManagedPolicyStatus> fetchPolicy() async {
    final session = await _requiredSession();
    final response = await _dio.get<Map<String, Object?>>(
      '/api/client/policies/current',
      queryParameters: {'deviceId': session.deviceId},
    );
    final envelope = response.data ?? const <String, Object?>{};
    final algorithm = envelope['signatureAlgorithm']?.toString() ?? '';
    final payload = envelope['payloadJson']?.toString() ?? '';
    final signature = envelope['signature']?.toString() ?? '';
    if (algorithm != 'HMAC-SHA256-HEX' ||
        payload.isEmpty ||
        signature.isEmpty ||
        session.policySignatureKey.isEmpty) {
      throw const FormatException('终端安全策略签名材料无效');
    }
    final expected = Hmac(
      sha256,
      utf8.encode(session.policySignatureKey),
    ).convert(utf8.encode(payload)).toString();
    if (!_constantTimeEquals(expected, signature)) {
      throw const FormatException('终端安全策略签名校验失败');
    }
    final policy = (jsonDecode(payload) as Map).cast<String, Object?>();
    return ManagedPolicyStatus(
      policyVersion: envelope['policyVersion']?.toString() ?? '',
      publishedAt: DateTime.tryParse(envelope['publishedAt']?.toString() ?? ''),
      enabled: policy['enabled'] == true,
      signatureVerified: true,
    );
  }

  Future<List<ManagedTerminalCommand>> fetchCommands({
    MobileSession? forSession,
  }) async {
    final session = forSession ?? await _requiredSession();
    final response = await _dio
        .get<List<Object?>>(
          '/api/client/commands',
          queryParameters: {'deviceId': session.deviceId},
          options: Options(
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'X-Device-Id': session.deviceId,
            },
          ),
        )
        .timeout(const Duration(seconds: 12));
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (item) =>
              ManagedTerminalCommand.fromJson(item.cast<String, Object?>()),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<void> completeCommand(
    String commandId, {
    required bool succeeded,
    required String resultMessage,
    MobileSession? forSession,
  }) async {
    final session = forSession ?? await _requiredSession();
    await _dio.post<void>(
      '/api/client/commands/$commandId/complete',
      data: {
        'deviceId': session.deviceId,
        'succeeded': succeeded,
        'resultMessage': resultMessage,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'X-Device-Id': session.deviceId,
        },
      ),
    );
  }

  Future<MobileSession> _requiredSession() async {
    final session = await _sessionStore.readSession();
    if (session == null ||
        session.accessToken.isEmpty ||
        session.deviceId.isEmpty) {
      throw StateError('登录状态已失效，请重新登录');
    }
    return session;
  }
}

final class ManagedTerminalCommandCoordinator {
  ManagedTerminalCommandCoordinator(this._ref);

  final Ref _ref;
  Timer? _timer;
  bool _checking = false;
  bool _running = false;
  int _generation = 0;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final generation = _generation;
    await synchronizeNow();
    if (!_running || generation != _generation) return;
    _timer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => synchronizeNow().ignore(),
    );
  }

  void stop() {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> synchronizeNow() async {
    if (_checking) return;
    _checking = true;
    final generation = _generation;
    try {
      final session = await _ref.read(secureSessionStoreProvider).readSession();
      if (session == null) return;
      final repository = _ref.read(managedSecurityRepositoryProvider);
      final commands = await repository.fetchCommands(forSession: session);
      if (generation != _generation || !_ref.mounted) return;
      for (final command in commands) {
        final current = await _ref
            .read(secureSessionStoreProvider)
            .readSession();
        if (current == null || !current.isSameSession(session)) return;
        final expiresAt = command.expiresAt;
        if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
          await _report(repository, command.id, false, '终端指令已过期。', session);
          continue;
        }
        if (command.commandType == 3) {
          await _report(
            repository,
            command.id,
            true,
            'Android 终端已收到强制下线指令。',
            session,
          );
          if (generation != _generation || !_ref.mounted) return;
          await _ref
              .read(authControllerProvider.notifier)
              .logout(clearCredential: true, expectedSession: session);
          // Logout includes an asynchronous push unregister; a newer login
          // may finish meanwhile. Do not stop that session's command polling.
          if (_ref.mounted &&
              await _ref.read(secureSessionStoreProvider).readSession() ==
                  null) {
            stop();
          }
          return;
        }
        await _report(
          repository,
          command.id,
          false,
          'Android 终端不支持桌面截屏或录屏指令。',
          session,
        );
      }
    } on DioException catch (error) {
      if (generation == _generation && _ref.mounted) {
        final terminated = await _ref
            .read(authControllerProvider.notifier)
            .handleSessionFailure(error);
        if (terminated) stop();
      }
    } catch (_) {
      // The next foreground synchronization or polling cycle retries safely.
    } finally {
      _checking = false;
    }
  }

  static Future<void> _report(
    ManagedSecurityRepository repository,
    String commandId,
    bool succeeded,
    String message,
    MobileSession session,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await repository.completeCommand(
          commandId,
          succeeded: succeeded,
          resultMessage: message,
          forSession: session,
        );
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    throw lastError ?? StateError('终端指令结果回传失败');
  }
}

int _integer(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

bool _constantTimeEquals(String left, String right) {
  final a = utf8.encode(left.trim().toLowerCase());
  final b = utf8.encode(right.trim().toLowerCase());
  var difference = a.length ^ b.length;
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    difference |= a[index % a.length] ^ b[index % b.length];
  }
  return difference == 0;
}
