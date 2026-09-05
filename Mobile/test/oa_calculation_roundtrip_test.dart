import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_request_page.dart';

class _Fixture {
  OaApprovalDraft? draft;
  Map<String, Object?>? preview;
}

Future<_Fixture> _open(
  WidgetTester tester, {
  required String amountExpression,
  required String costExpression,
  OaApprovalDraft? restored,
}) async {
  final fixture = _Fixture()..draft = restored;
  final template = OaApprovalTemplate(
    id: 'precision-template',
    name: 'AI-UAT 计算精度',
    category: '财务',
    iconKey: 'payment',
    workflowKey: 'precision-test',
    version: 1,
    formSchemaJson: jsonEncode({
      'fields': [
        {'id': 'input', 'label': '原始费用', 'type': 'amount', 'required': true},
        {
          'id': 'amount',
          'label': '请款金额',
          'type': 'amount',
          'required': true,
          'unit': 'USDT',
          'calculation': {
            'expression': amountExpression,
            'scale': 2,
            'roundingMode': 'half_up',
          },
        },
        {
          'id': 'cost',
          'label': '成本',
          'type': 'amount',
          'required': true,
          'unit': 'CNY',
          'calculation': {
            'expression': costExpression,
            'scale': 2,
            'roundingMode': 'half_up',
          },
        },
        {'id': 'reason', 'label': '测试说明', 'type': 'text', 'required': true},
      ],
    }),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => OaBootstrap(
            displayName: 'AI-UAT',
            todos: const [],
            announcements: const [],
            templates: [template],
          ),
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => OaApplicationCatalog.fromJson({
            'catalogVersion': 'precision-test',
            'items': [{
              'applicationKey': 'precision-test', 'name': 'AI-UAT 计算精度',
              'category': '财务', 'iconKey': 'payment',
              'configurationKind': 'approval', 'approvalTemplateId': template.id,
              'allowOfflineDraft': true, 'availabilitySource': 'department',
            }],
          }),
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        imDepartmentsProvider.overrideWith((ref) async => const []),
        oaDraftLoaderProvider.overrideWithValue((_) async => fixture.draft),
        oaDraftSaverProvider.overrideWithValue(({
          String? id,
          required String applicationKey,
          required OaApprovalTemplate template,
          required String title,
          required Map<String, Object?> formData,
          required List<OaLocalAttachment> attachments,
        }) async {
          final encoded =
              jsonDecode(jsonEncode(formData)) as Map<String, dynamic>;
          return fixture.draft = OaApprovalDraft(
            id: id ?? 'precision-draft',
            applicationKey: applicationKey,
            templateId: template.id,
            workflowKey: template.workflowKey,
            title: 'AI-UAT 精度草稿',
            formData: encoded,
            updatedAt: DateTime.utc(2026, 9, 3),
            attachments: attachments,
          );
        }),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(({
          required String applicationKey,
          required OaApprovalTemplate template,
          required Map<String, Object?> formData,
        }) async {
          fixture.preview =
              jsonDecode(jsonEncode(formData)) as Map<String, dynamic>;
          return PreviewData.workflowPreview(template);
        }),
      ],
      child: const MaterialApp(
        home: ApprovalRequestPage(
          applicationKey: 'precision-test',
          templateId: 'precision-template',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _edit(WidgetTester tester, String input) async {
  await tester.enterText(find.byKey(const ValueKey('schema-input')), input);
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, String id, String value) =>
    tester.widget<TextField>(
      find.descendant(
        of: find.byKey(ValueKey('schema-$id-$value')),
        matching: find.byType(TextField),
      ),
    );

void main() {
  testWidgets(
    'rounded decimal fields display save and preview the same values',
    (tester) async {
      final fixture = await _open(
        tester,
        amountExpression: 'input',
        costExpression: 'amount * 3',
      );
      await _edit(tester, '1.005');
      final amount = _field(tester, 'amount', '1.01');
      expect(amount.controller?.text, '1.01');
      expect(amount.readOnly, isTrue);
      expect(amount.canRequestFocus, isFalse);
      expect(amount.decoration?.suffixText, 'USDT');
      expect(_field(tester, 'cost', '3.03').decoration?.suffixText, 'CNY');
      expect(fixture.draft?.formData['amount'], 1.01);
      expect(fixture.preview?['amount'], 1.01);
      expect(fixture.draft?.formData['cost'], 3.03);
      expect(fixture.preview?['cost'], 3.03);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'large decimal text survives draft restoration and chained subtraction',
    (tester) async {
      final fixture = await _open(
        tester,
        amountExpression: 'input + 0.01',
        costExpression: 'amount - input',
      );
      await _edit(tester, '90071992547409.92');
      expect(
        _field(tester, 'amount', '90071992547409.93').controller?.text,
        '90071992547409.93',
      );
      expect(_field(tester, 'cost', '0.01').controller?.text, '0.01');
      expect(fixture.draft?.formData['amount'], '90071992547409.93');
      expect(fixture.preview?['amount'], '90071992547409.93');
      final saved = fixture.draft!;
      await tester.pumpWidget(const SizedBox.shrink());
      await _open(
        tester,
        amountExpression: 'input + 0.01',
        costExpression: 'amount - input',
        restored: saved,
      );
      expect(
        _field(tester, 'amount', '90071992547409.93').controller?.text,
        '90071992547409.93',
      );
      expect(_field(tester, 'cost', '0.01').controller?.text, '0.01');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'precision overflow removes stale computed values and recovers on edit',
    (tester) async {
      final fixture = await _open(
        tester,
        amountExpression: 'input',
        costExpression: 'amount * 3',
      );
      await _edit(tester, '1.005');
      await _edit(tester, '79228162514264337593543950336');
      expect(_field(tester, 'amount', '').controller?.text, '');
      expect(fixture.draft?.formData.containsKey('amount'), isFalse);
      expect(fixture.draft?.formData.containsKey('cost'), isFalse);
      await tester.tap(find.byKey(const Key('approval-submit-button')));
      await tester.pumpAndSettle();
      expect(find.text('结果超出 decimal 精度'), findsOneWidget);
      await _edit(tester, '1.005');
      expect(find.text('结果超出 decimal 精度'), findsNothing);
      expect(_field(tester, 'amount', '1.01').controller?.text, '1.01');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
