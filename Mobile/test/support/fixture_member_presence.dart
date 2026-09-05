import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

/// Explicit live samples for presentation tests whose API providers are mocked.
/// Cold-cache and lifecycle tests use the actual projection instead.
class FixtureMemberPresence extends ImMemberPresenceProjection {
  FixtureMemberPresence(this.members);
  final Iterable<ImMember> members;

  @override
  Map<String, ImMemberPresenceObservation> build() => {
    for (final member in members)
      member.id: ImMemberPresenceObservation(
        online: member.isOnline,
        order: 1,
        lastSeenAt: member.lastSeenAt,
      ),
  };
}
