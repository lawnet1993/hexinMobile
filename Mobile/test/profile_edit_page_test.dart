import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/profile_edit_page.dart';

void main() {
  testWidgets(
    'profile edit renders cached identity while remote sync is pending',
    (tester) async {
      final remote = Completer<ImMemberProfile>();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ProfileAuthController.new),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imMemberProfileLoaderProvider.overrideWithValue(
            (memberId) => remote.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(imBootstrapProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ProfileEditPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('个人资料'), findsOneWidget);
      expect(find.text('资料同步中'), findsOneWidget);
      expect(find.text('昵称'), findsOneWidget);
      expect(find.text('个性签名'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('profile-sync-state'))).height,
        30,
      );
      expect(
        tester.getSize(find.byKey(const Key('profile-nickname-field'))).height,
        40,
      );
      expect(
        tester.getSize(find.byKey(const Key('profile-signature-field'))).height,
        72,
      );
      expect(
        tester.getSize(find.byKey(const Key('profile-save-button'))),
        const Size(104, 36),
      );
      expect(find.textContaining('账号'), findsNothing);

      remote.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();

      expect(find.text('当前显示本机资料'), findsOneWidget);
      expect(find.text('重新同步'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('profile-signature-field')),
          matching: find.byType(TextField),
        ),
        '离线编辑内容',
      );
      await tester.pump();
      final saveButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(saveButton.onPressed, isNotNull);
    },
  );

  testWidgets('profile edit falls back to the authenticated session', (
    tester,
  ) async {
    final bootstrap = Completer<ImBootstrap>();
    addTearDown(() {
      if (!bootstrap.isCompleted) {
        bootstrap.completeError(StateError('offline'));
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_ProfileAuthController.new),
          imBootstrapProvider.overrideWith((ref) => bootstrap.future),
          imMemberProfileLoaderProvider.overrideWithValue(
            (_) => Future<ImMemberProfile>.error(StateError('offline')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ProfileEditPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('林川'), findsOneWidget);
    expect(find.text('暂时无法读取个人资料'), findsNothing);
  });

  for (final change in ['account', 'rotation', 'logout']) {
    testWidgets('pending profile isolates late content after $change', (
      tester,
    ) async {
      final pending = Completer<ImMemberProfile>();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_SwitchableProfileAuth.new),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imMemberProfileLoaderProvider.overrideWithValue(
            (_) => pending.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      await container.read(imBootstrapProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ProfileEditPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'old-account-draft');
      (container.read(
        authControllerProvider.notifier,
      ) as _SwitchableProfileAuth).change(change);
      await tester.pump();
      pending.complete(
        const ImMemberProfile(
          id: 'me',
          displayName: 'Late old profile',
          username: 'old',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Late old profile'), findsNothing);
      if (change == 'rotation') {
        expect(find.text('old-account-draft'), findsOneWidget);
        expect(find.byKey(const Key('profile-save-button')), findsOneWidget);
        expect(find.text('登录状态已更新，请返回后重试'), findsNothing);
      } else {
        expect(find.text('old-account-draft'), findsNothing);
        expect(find.byKey(const Key('profile-save-button')), findsNothing);
        expect(find.text('登录状态已更新，请返回后重试'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('avatar picker completion is discarded after $change', (
      tester,
    ) async {
      final picked = Completer<ProfileAvatarSelection?>();
      var repositoryReads = 0;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_SwitchableProfileAuth.new),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imMemberProfileLoaderProvider.overrideWithValue(
            (_) async => const ImMemberProfile(
              id: 'me',
              displayName: 'Fixture',
              username: 'test-user',
            ),
          ),
          profileAvatarPickerProvider.overrideWithValue(() => picked.future),
          imRepositoryProvider.overrideWith((ref) {
            repositoryReads++;
            throw StateError('stale picker must not upload');
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      await container.read(imBootstrapProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ProfileEditPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-avatar-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('阿晨'), findsOneWidget);
      expect(find.text('若岚'), findsOneWidget);
      expect(find.text('相册'), findsOneWidget);
      await tester.tap(find.text('相册'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      (container.read(
        authControllerProvider.notifier,
      ) as _SwitchableProfileAuth).change(change);
      picked.complete((
        name: 'fixture.png',
        path: '',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));
      await tester.pumpAndSettle();
      expect(repositoryReads, 0);
      expect(find.textContaining('头像更新失败'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retrying a cached profile keeps current edits', (tester) async {
    final remote = Completer<ImMemberProfile>();
    var loads = 0;
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_ProfileAuthController.new),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        imMemberProfileLoaderProvider.overrideWithValue((_) {
          if (++loads == 1) return Future.error(StateError('offline'));
          return remote.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(imBootstrapProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ProfileEditPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'keep this draft');
    await tester.tap(find.text('重新同步'));
    await tester.pump();
    expect(find.text('keep this draft'), findsOneWidget);
    remote.complete(
      const ImMemberProfile(
        id: 'me',
        displayName: 'Remote',
        username: 'test-user',
        signature: 'server old text',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('keep this draft'), findsOneWidget);
    expect(find.text('server old text'), findsNothing);
  });
}

final class _ProfileAuthController extends AuthController {
  @override
  Future<MobileSession?> build() async => const MobileSession(
    accessToken: 'test-token',
    deviceId: 'test-device',
    userId: 'me',
    displayName: '林川',
    username: 'test-user',
    policySignatureKey: 'test-key',
    imApiUrl: 'https://im.invalid',
    oaApiUrl: 'https://oa.invalid',
  );

  @override
  Future<SavedCredential?> savedCredential() async => null;
}

final class _SwitchableProfileAuth extends _ProfileAuthController {
  void change(String kind) => state = AsyncData(
    kind == 'logout'
        ? null
        : MobileSession(
            accessToken: 'fixture-new',
            deviceId: 'test-device',
            userId: kind == 'account' ? 'other' : 'me',
            username: kind == 'account' ? 'other-user' : 'test-user',
            displayName: 'New user',
            policySignatureKey: '',
            imApiUrl: '',
            oaApiUrl: '',
          ),
  );
}
