import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_request_page.dart';

Future<void> openForm(
  WidgetTester tester, {
  required String kind,
  required bool readOnly,
  required Object value,
  required void Function(Map<String, Object?>, List<OaLocalAttachment>) onSave,
}) async {
  final attachment = kind == 'file' || kind == 'attachment';
  final template = OaApprovalTemplate(
    id: 'readonly-fixture',
    name: '配置表单',
    category: '测试',
    iconKey: 'file',
    workflowKey: 'test',
    version: 1,
    formSchemaJson: jsonEncode({
      'fields': [
        {
          'id': 'configured',
          'label': '配置字段',
          'type': kind,
          'readOnly': readOnly,
          'options': ['甲', '乙'],
        },
      ],
    }),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationAccountScopeProvider.overrideWithValue('test-account'),
        oaBootstrapProvider.overrideWith(
          (ref) async => OaBootstrap(
            currentMemberId: 'test-account',
            displayName: '测试',
            todos: const [],
            announcements: const [],
            templates: [template],
          ),
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        imDepartmentsProvider.overrideWith((ref) async => const []),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
        oaDraftSaverProvider.overrideWithValue(({
          String? id,
          required String applicationKey,
          required OaApprovalTemplate template,
          required String title,
          required Map<String, Object?> formData,
          required List<OaLocalAttachment> attachments,
        }) async {
          onSave(Map.of(formData), List.of(attachments));
          return OaApprovalDraft(
            id: id!,
            applicationKey: applicationKey,
            templateId: template.id,
            workflowKey: template.workflowKey,
            title: title,
            formData: formData,
            attachments: attachments,
            updatedAt: DateTime(2026, 9, 5),
          );
        }),
      ],
      child: MaterialApp(
        home: ApprovalRequestPage(
          applicationKey: 'attendance.leave',
          templateId: template.id,
          initialFormData: {'configured': value},
          initialAttachments: attachment
              ? const [
                  OaLocalAttachment(
                    id: 'proof',
                    fileName: 'AI-UAT-proof.txt',
                    contentType: 'text/plain',
                    bytes: [65],
                    formFieldId: 'configured',
                  ),
                ]
              : const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [
    'checkbox',
    'select',
    'multiSelect',
    'person',
    'department',
    'date',
    'datetime',
    'dateRange',
  ]) {
    for (final readOnly in [true, false]) {
      testWidgets('configured $kind respects readOnly=$readOnly', (
        tester,
      ) async {
        final requester = PreviewData.imBootstrap.currentMember;
        final Object value = switch (kind) {
          'checkbox' => true,
          'select' => '甲',
          'multiSelect' => ['甲'],
          'person' => requester.id,
          'department' => requester.departmentId,
          'date' => '2026-09-05',
          'datetime' => '2026-09-05T09:00:00',
          _ => ['2026-09-05', '2026-09-06'],
        };
        Map<String, Object?>? saved;
        await openForm(
          tester,
          kind: kind,
          readOnly: readOnly,
          value: value,
          onSave: (data, _) => saved = data,
        );
        final field = find
            .byWidgetPredicate((w) => w is FormField && w is! TextFormField)
            .first;
        if (kind == 'checkbox') {
          final checkbox = find.byType(CheckboxListTile);
          expect(
            tester.widget<CheckboxListTile>(checkbox).onChanged,
            readOnly ? isNull : isNotNull,
          );
          if (readOnly) await tester.tap(checkbox);
        } else {
          final ink = find
              .descendant(of: field, matching: find.byType(InkWell))
              .first;
          expect(
            tester.widget<InkWell>(ink).onTap,
            readOnly ? isNull : isNotNull,
          );
          await tester.tap(ink);
          await tester.pumpAndSettle();
          expect(
            find.byType(BottomSheet),
            readOnly ? findsNothing : findsOneWidget,
          );
          if (!readOnly) {
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.byKey(const Key('approval-draft-button')));
        await tester.pumpAndSettle();
        expect(saved?['configured'], value);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final kind in ['file', 'attachment']) {
    for (final readOnly in [true, false]) {
      testWidgets('$kind readOnly=$readOnly retains preview but not mutation', (
        tester,
      ) async {
        List<OaLocalAttachment>? saved;
        await openForm(
          tester,
          kind: kind,
          readOnly: readOnly,
          value: '',
          onSave: (_, attachments) => saved = attachments,
        );
        expect(find.text('替换文件'), readOnly ? findsNothing : findsOneWidget);
        expect(
          find.byTooltip('删除附件'),
          readOnly ? findsNothing : findsOneWidget,
        );
        final row = find.byKey(const ValueKey('approval-attachment-proof'));
        expect(
          tester
              .widget<InkWell>(
                find.descendant(of: row, matching: find.byType(InkWell)).first,
              )
              .onTap,
          isNotNull,
        );
        await tester.tap(find.byKey(const Key('approval-draft-button')));
        await tester.pumpAndSettle();
        expect(saved!.single.id, 'proof');
        expect(saved!.single.bytes, [65]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
