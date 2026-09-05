import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_presence_projection.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  final real = DateTime.utc(2026, 9, 4, 15);
  for (final raw in [
    '1970-01-01T00:00:00Z',
    '1970-01-01T08:00:00+08:00',
    '0001-01-01T00:00:00Z',
  ]) {
    test('member decoding rejects default presence time $raw', () {
      final member = ImMember.fromJson({
        'id': 'peer',
        'isOnline': false,
        'lastSeenAt': raw,
      });
      expect(member.lastSeenAt, isNull);
      expect(member.presenceKnown, true);
      expect(member.isOnline, false);
    });
    test('direct presence decoding rejects default time $raw', () {
      final value = ImConversationPresence.fromJson({
        'type': 'direct',
        'peerOnline': false,
        'peerLastSeenAt': raw,
      });
      expect(value.peerLastSeenAt, isNull);
      expect(value.peerPresenceKnown, true);
      expect(value.peerOnline, false);
    });
    test('old cache and observations cannot display default time $raw', () {
      final sentinel = DateTime.parse(raw);
      final member = ImMember(
        id: 'peer',
        username: 'peer',
        displayName: 'Peer',
        isOnline: false,
        lastSeenAt: sentinel,
      );
      final sample = ImMemberPresenceObservation(
        online: false,
        order: 1,
        lastSeenAt: sentinel,
      );
      for (final transport in [true, false]) {
        final result = resolveMemberPresence(
          transportAvailable: transport,
          member: member,
          observation: sample,
        );
        expect(result.lastSeenAt, isNull);
        expect(result.online, transport ? false : null);
        final direct = resolveDirectPeerPresence(
          transportAvailable: transport,
          member: member,
        );
        expect(direct.lastSeenAt, isNull);
        expect(direct.online, isNull);
      }
    });
  }
  test('real historical activity survives a missing or default new value', () {
    final sentinel = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    expect(latestPresenceTime(real, sentinel), real);
    expect(latestPresenceTime(sentinel, real), real);
    expect(latestPresenceTime(sentinel, null), isNull);
    expect(latestPresenceTime(null, sentinel), isNull);
    final later = real.add(const Duration(minutes: 1));
    expect(latestPresenceTime(real, later), later);
  });
  test(
    'real January first is retained, not rejected by its formatted date',
    () {
      final january = DateTime.utc(2026, 1, 1);
      expect(
        ImMember.fromJson({'lastSeenAt': january.toIso8601String()}).lastSeenAt
            ?.toUtc(),
        january,
      );
    },
  );
  test('direct default observation falls back to valid member activity', () {
    final member = ImMember(
      id: 'peer',
      username: 'peer',
      displayName: 'Peer',
      isOnline: false,
      lastSeenAt: real,
    );
    final direct = ImConversationPresence.fromJson({
      'type': 'direct',
      'peerOnline': false,
      'peerLastSeenAt': '1970-01-01T00:00:00Z',
    });
    final result = resolveDirectPeerPresence(
      transportAvailable: true,
      member: member,
      observation: ImPresenceObservation(direct),
    );
    expect(result.lastSeenAt, real);
    expect(result.online, false);
  });
}
