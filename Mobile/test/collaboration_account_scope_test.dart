import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';

void main() {
  test('collaboration cache scope follows the active login identity', () async {
    final container = ProviderContainer.test(
      overrides: [
        authControllerProvider.overrideWith(_SwitchableAuthController.new),
      ],
    );

    await container.read(authControllerProvider.future);
    final subscription = container.listen<String>(
      collaborationAccountScopeProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(container.read(collaborationAccountScopeProvider), 'account-a');

    final controller = container.read(authControllerProvider.notifier);
    (controller as _SwitchableAuthController).switchTo(_session('account-b'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(collaborationAccountScopeProvider), 'account-b');
  });
}

final class _SwitchableAuthController extends AuthController {
  @override
  Future<MobileSession?> build() async => _session('account-a');

  void switchTo(MobileSession session) => state = AsyncData(session);
}

MobileSession _session(String userId) => MobileSession(
  accessToken: 'test-token-$userId',
  deviceId: 'test-device',
  userId: userId,
  displayName: userId,
  username: userId,
  policySignatureKey: 'test-key',
  imApiUrl: 'https://im.invalid',
  oaApiUrl: 'https://oa.invalid',
);
