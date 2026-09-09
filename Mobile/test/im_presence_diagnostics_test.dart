import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_presence_diagnostics.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_presence_projection.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  const value = ImConversationPresence(
    conversationId: 'fixture-direct',
    type: 'direct',
    onlineMemberCount: 0,
    peerOnline: false,
  );
  test('presence telemetry is disabled unless explicitly enabled', () {
    final lines = <String>[];
    final diagnostics = ImPresenceDiagnostics(write: lines.add);
    diagnostics.response(
      value,
      status: 200,
      host: 'localhost',
      startedAt: DateTime(2026),
    );
    diagnostics.render(
      'fixture-direct',
      displayedOnline: null,
      transportAvailable: false,
      member: null,
      conversation: null,
    );
    expect(lines, isEmpty);
  });
  test('response telemetry has a fixed non-secret field allowlist', () {
    final lines = <String>[];
    ImPresenceDiagnostics(enabled: true, write: lines.add).response(
      value,
      status: 200,
      host: 'localhost',
      startedAt: DateTime.utc(2026),
    );
    final data =
        jsonDecode(lines.single.split('MOBILE_IM_PRESENCE ').last) as Map;
    expect(data.keys.toSet(), {
      'sampledAt',
      'kind',
      'conversationId',
      'conversationType',
      'httpStatus',
      'host',
      'startedAt',
      'peerOnline',
      'peerPresenceKnown',
      'peerLastSeenAt',
      'onlineMemberCount',
      'serverTime',
    });
    expect(data['peerOnline'], false);
    expect(data['peerLastSeenAt'], isNull);
    expect(data['kind'], 'response');
  });
  test('member telemetry reports only aggregate presence coverage', () {
    final lines = <String>[];
    ImPresenceDiagnostics(enabled: true, write: lines.add).memberResponse(
      [
        const ImMember(
          id: 'hidden-1',
          username: 'secret-account',
          displayName: 'Hidden Person',
          isOnline: true,
        ),
        const ImMember(
          id: 'hidden-2',
          username: 'secret-account-2',
          displayName: 'Hidden Person 2',
          isOnline: false,
          presenceKnown: false,
        ),
      ],
      source: 'bootstrap',
      status: 200,
    );
    final data =
        jsonDecode(lines.single.split('MOBILE_IM_PRESENCE ').last) as Map;
    expect(data.keys.toSet(), {
      'sampledAt',
      'kind',
      'source',
      'httpStatus',
      'received',
      'presenceKnown',
      'online',
      'withLastSeen',
    });
    expect(data['received'], 2);
    expect(data['presenceKnown'], 1);
    expect(data['online'], 1);
    expect(data['withLastSeen'], 0);
    expect(lines.single, isNot(contains('hidden-1')));
    expect(lines.single, isNot(contains('secret-account')));
    expect(lines.single, isNot(contains('Hidden Person')));
  });
  test(
    'render telemetry preserves unknown and distinguishes projection sources',
    () {
      final lines = <String>[];
      ImPresenceDiagnostics(enabled: true, write: lines.add).render(
        'fixture-direct',
        displayedOnline: null,
        transportAvailable: false,
        member: const ImMemberPresenceObservation(
          online: true,
          order: 4,
          fresh: false,
        ),
        conversation: const ImPresenceObservation(value),
      );
      final data =
          jsonDecode(lines.single.split('MOBILE_IM_PRESENCE ').last) as Map;
      expect(data.keys.toSet(), {
        'sampledAt',
        'kind',
        'conversationId',
        'displayedOnline',
        'transportAvailable',
        'memberOnline',
        'memberFresh',
        'memberOrder',
        'memberLastSeenAt',
        'conversationOnline',
        'conversationFresh',
        'conversationServerTime',
      });
      expect(data['displayedOnline'], isNull);
      expect(data['memberOnline'], true);
      expect(data['memberFresh'], false);
      expect(data['conversationOnline'], false);
    },
  );
}
