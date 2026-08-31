import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';

void main() {
  testWidgets('opening an unread copied approval synchronizes cc read', (
    tester,
  ) async {
    final markedRequestIds = <String>[];
    final original = PreviewData.oaBootstrap.approvalRequests.first;
    final request = OaApprovalRequest(
      id: 'approval-copy-1',
      requesterId: original.requesterId,
      title: original.title,
      formDataJson: original.formDataJson,
      formSchemaSnapshotJson: original.formSchemaSnapshotJson,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
      requesterName: original.requesterName,
      requesterDepartmentName: original.requesterDepartmentName,
      templateName: original.templateName,
      templateCategory: original.templateCategory,
      allowedActions: const [],
      tasks: const [],
      actions: const [],
      attachments: const [],
      ccs: const [
        OaApprovalCc(
          id: 'cc-1',
          memberId: 'member-current',
          memberName: '当前成员',
          isRead: false,
          createdAt: null,
          readAt: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          markApprovalCcReadActionProvider.overrideWithValue((id) async {
            markedRequestIds.add(id);
          }),
          oaApprovalRequestProvider(request.id)
              .overrideWith((ref) async => request),
          oaBootstrapProvider.overrideWith(
            (ref) async => const OaBootstrap(
              currentMemberId: 'member-current',
              displayName: '当前成员',
              todos: [],
              announcements: [],
              templates: [],
            ),
          ),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          oaNotificationsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(home: ApprovalDetailPage(approvalId: request.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(markedRequestIds, ['approval-copy-1']);
    expect(tester.takeException(), isNull);
  });
}
