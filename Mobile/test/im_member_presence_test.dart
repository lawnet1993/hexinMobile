import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

const _session = MobileSession(
  accessToken: 'fixture',
  deviceId: 'fixture',
  userId: 'self',
  displayName: 'Self',
  username: 'self',
  policySignatureKey: '',
  imApiUrl: '',
  oaApiUrl: '',
);

class _Auth extends AuthController {
  @override
  Future<MobileSession?> build() async => _session;
  void replace(MobileSession? session) => state = AsyncData(session);
}

ImMember _member(bool online, {String id = 'peer', DateTime? seen}) => ImMember(
  id: id,
  username: id,
  displayName: id,
  isOnline: online,
  lastSeenAt: seen,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late ImMemberPresenceProjection projection;
  setUp(() async {
    container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(_Auth.new)],
    );
    await container.read(authControllerProvider.future);
    projection = container.read(imMemberPresenceProjectionProvider.notifier);
  });
  tearDown(() => container.dispose());

  test(
    'new group sample wins over a late directory response and vice versa',
    () {
      final directory = projection.beginRequest();
      final group = projection.beginRequest();
      projection.observe(_session, group, [_member(false)]);
      projection.observe(_session, directory, [_member(true)]);
      expect(
        container.read(imMemberPresenceProjectionProvider)['peer']!.online,
        false,
      );
      final freshDirectory = projection.beginRequest();
      projection.observe(_session, freshDirectory, [_member(true)]);
      projection.observe(_session, group, [_member(false)]);
      expect(
        container.read(imMemberPresenceProjectionProvider)['peer']!.online,
        true,
      );
    },
  );

  test(
    'offline samples are ordered by request, never by last-seen activity',
    () {
      final seen = DateTime.utc(2026, 9, 3);
      projection.observe(_session, projection.beginRequest(), [
        _member(true, seen: seen),
      ]);
      projection.observe(_session, projection.beginRequest(), [
        _member(false, seen: seen),
      ]);
      final value = container.read(imMemberPresenceProjectionProvider)['peer']!;
      expect(value.online, false);
      expect(value.lastSeenAt, seen);
    },
  );

  test('cache alone and transport failure never assert online or offline', () {
    final seen = DateTime.utc(2026, 9, 3);
    final member = _member(true, seen: seen);
    expect(
      resolveMemberPresence(transportAvailable: true, member: member).online,
      isNull,
    );
    final result = resolveMemberPresence(
      transportAvailable: false,
      member: member,
      observation: ImMemberPresenceObservation(
        online: true,
        order: 1,
        lastSeenAt: seen,
      ),
    );
    expect(result.online, isNull);
    expect(result.lastSeenAt, seen);
  });

  test('missing or malformed presence is unknown, not offline', () {
    for (final raw in [null, 'unknown', 2, <String, Object?>{}]) {
      final member = ImMember.fromJson({'id': 'peer', 'isOnline': raw});
      expect(member.presenceKnown, false);
      projection.observe(_session, projection.beginRequest(), [member]);
      expect(
        container.read(imMemberPresenceProjectionProvider)['peer']!.online,
        isNull,
      );
    }
    final offline = ImMember.fromJson({'id': 'peer', 'isOnline': false});
    expect(offline.presenceKnown, true);
    projection.observe(_session, projection.beginRequest(), [offline]);
    expect(
      container.read(imMemberPresenceProjectionProvider)['peer']!.online,
      false,
    );
    expect(
      ImConversationPresence.fromJson({'type': 'direct'}).peerPresenceKnown,
      false,
    );
  });

  testWidgets(
    'expiry starts at request dispatch and a delayed response cannot renew it',
    (tester) async {
      final request = projection.beginRequest();
      await tester.pump(const Duration(seconds: 45));
      projection.observe(_session, request, [_member(true)]);
      expect(
        container.read(imMemberPresenceProjectionProvider)['peer']!.fresh,
        true,
      );
      await tester.pump(const Duration(seconds: 16));
      final value = container.read(imMemberPresenceProjectionProvider)['peer']!;
      expect(value.fresh, false);
      projection.observe(_session, request, [_member(true)]);
      expect(
        container.read(imMemberPresenceProjectionProvider)['peer']!.fresh,
        false,
      );
      expect(
        resolveMemberPresence(
          transportAvailable: true,
          observation: value,
        ).online,
        isNull,
      );
    },
  );

  testWidgets('older batch expiry cannot invalidate a newer observation', (
    tester,
  ) async {
    projection.observe(_session, projection.beginRequest(), [_member(true)]);
    await tester.pump(const Duration(seconds: 30));
    projection.observe(_session, projection.beginRequest(), [_member(false)]);
    await tester.pump(const Duration(seconds: 31));
    expect(
      container.read(imMemberPresenceProjectionProvider)['peer']!.fresh,
      true,
    );
    expect(
      container.read(imMemberPresenceProjectionProvider)['peer']!.online,
      false,
    );
    await tester.pump(const Duration(seconds: 30));
  });

  for (final next in <MobileSession?>[
    _session.withTokens(accessToken: 'fixture-new'),
    null,
    const MobileSession(
      accessToken: 'other',
      deviceId: 'other',
      userId: 'other',
      displayName: 'Other',
      username: 'other',
      policySignatureKey: '',
      imApiUrl: '',
      oaApiUrl: '',
    ),
  ]) {
    test(
      'session reset rejects captured presence requests ${next?.userId ?? 'logout'}',
      () {
        final old = projection.beginRequest();
        projection.observe(_session, old, [_member(true)]);
        (container.read(authControllerProvider.notifier) as _Auth).replace(
          next,
        );
        expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
        projection.observe(_session, old, [_member(true)]);
        expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
      },
    );
  }

  test(
    'large batches are bounded and empty pages do not clear other members',
    () {
      projection.observe(
        _session,
        projection.beginRequest(),
        List.generate(3000, (index) => _member(false, id: 'member-$index')),
      );
      expect(
        container.read(imMemberPresenceProjectionProvider),
        hasLength(2048),
      );
      projection.observe(_session, projection.beginRequest(), []);
      expect(
        container.read(imMemberPresenceProjectionProvider),
        hasLength(2048),
      );
      for (var index = 0; index < 129; index++) {
        projection.beginRequest();
      }
      expect(
        container
            .read(imMemberPresenceProjectionProvider)
            .values
            .every((value) => !value.fresh),
        true,
      );
    },
  );
}
