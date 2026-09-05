import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_request_page.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_bottom_sheets.dart';

Future<Object?> _picker(BuildContext context, String kind) => switch (kind) {
  'date' => showMobileDatePickerSheet(
    context,
    initialDate: DateTime(2026, 9, 3),
    firstDate: DateTime(2026),
    lastDate: DateTime(2027),
  ),
  'range' => showMobileDateRangePickerSheet(
    context,
    initialDateRange: DateTimeRange(
      start: DateTime(2026, 9, 3),
      end: DateTime(2026, 9, 4),
    ),
    firstDate: DateTime(2026),
    lastDate: DateTime(2027),
  ),
  'time' => showMobileTimePickerSheet(
    context,
    initialTime: const TimeOfDay(hour: 9, minute: 30),
  ),
  'choice' => showMobileChoiceSheet(
    context,
    title: '类型',
    options: const [MobileSheetOption(value: 'a', label: '选项 A')],
  ),
  _ => showMobileMultiChoiceSheet(
    context,
    title: '类型',
    options: const [MobileSheetOption(value: 'a', label: '选项 A')],
    selectedValues: const ['a'],
  ),
};

void main() {
  testWidgets('searchable choice owns keyboard without restoring form focus', (
    tester,
  ) async {
    final focus = FocusNode();
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextField(focusNode: focus),
                InkWell(
                  onTap: () async {
                    result = await showMobileChoiceSheet<String>(
                      context,
                      title: '业务部门',
                      searchable: true,
                      options: List.generate(
                        20,
                        (index) => MobileSheetOption(
                          value: '$index',
                          label: '部门 $index',
                        ),
                      ),
                    );
                  },
                  child: const Text('打开部门'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.text('打开部门'));
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byKey(const Key('mobile-choice-sheet')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(search).autofocus, isTrue);
    await tester.enterText(search, '部门 19');
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.widgetWithText(ListTile, '部门 19'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    expect(result, '19');
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
  });

  for (final kind in ['date', 'range', 'time', 'choice', 'multi']) {
    for (final confirm in [false, true]) {
      testWidgets(
        '$kind picker ${confirm ? 'confirm' : 'back'} does not revive previous input focus',
        (tester) async {
          final focus = FocusNode();
          final controller = TextEditingController(text: '保留事由');
          Object? result;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      TextField(focusNode: focus, controller: controller),
                      InkWell(
                        onTap: () async {
                          result = await _picker(context, kind);
                        },
                        child: const Text('打开选择'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(TextField));
          await tester.pump();
          expect(focus.hasFocus, isTrue);
          await tester.tap(find.text('打开选择'));
          await tester.pumpAndSettle();
          if (!confirm) {
            await tester.binding.handlePopRoute();
          } else if (kind == 'choice') {
            await tester.tap(find.text('选项 A'));
          } else {
            await tester.tap(find.text(kind == 'multi' ? '确定（1）' : '确定'));
          }
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 350));
          expect(focus.hasFocus, isFalse);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(controller.text, '保留事由');
          expect(result, confirm ? isNotNull : isNull);
          // Explicitly tapping the original input must still work afterwards.
          await tester.tap(find.byType(TextField));
          await tester.pump();
          expect(focus.hasFocus, isTrue);
          await tester.pumpWidget(const SizedBox.shrink());
          focus.dispose();
          controller.dispose();
        },
      );
    }
  }

  for (final restored in [false, true]) {
    testWidgets('draft save keeps form geometry stable, restored=$restored', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final template = PreviewData.oaBootstrap.templates.first;
      OaApprovalDraft makeDraft(Map<String, Object?> values) => OaApprovalDraft(
        id: 'test-draft',
        applicationKey: 'attendance.leave',
        templateId: template.id,
        workflowKey: template.workflowKey,
        title: '测试草稿',
        formData: values,
        updatedAt: DateTime(2026, 9, 2, 23, 20),
        attachments: const [],
      );
      final save = Completer<OaApprovalDraft>();
      Map<String, Object?>? submitted;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith(
              (ref) async => PreviewData.oaBootstrap,
            ),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
            imBootstrapProvider.overrideWith(
              (ref) async => PreviewData.imBootstrap,
            ),
            imDepartmentsProvider.overrideWith((ref) async => const []),
            oaDraftLoaderProvider.overrideWithValue(
              (_) async => restored ? makeDraft({'reason': '恢复事由'}) : null,
            ),
            oaDraftSaverProvider.overrideWithValue(({
              String? id,
              required String applicationKey,
              required OaApprovalTemplate template,
              required String title,
              required Map<String, Object?> formData,
              required List<OaLocalAttachment> attachments,
            }) {
              submitted = Map.of(formData);
              return save.future;
            }),
            oaWorkflowPreviewLoaderProvider.overrideWithValue(
              ({
                required String applicationKey,
                required OaApprovalTemplate template,
                required Map<String, Object?> formData,
              }) async => PreviewData.workflowPreview(template),
            ),
          ],
          child: const MaterialApp(
            home: ApprovalRequestPage(
              applicationKey: 'attendance.leave',
              templateId: '1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final surface = find.byKey(const Key('approval-form-surface'));
      final before = tester.getTopLeft(surface);
      await tester.enterText(find.byType(TextFormField), 'AI-UAT-稳定表单');
      await tester.pump(const Duration(milliseconds: 650));
      expect(submitted?['reason'], 'AI-UAT-稳定表单');
      expect(tester.getTopLeft(surface), before);
      save.complete(makeDraft(submitted!));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(surface), before);
      expect(find.text('草稿已保存'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('approval-draft-status'))).height,
        lessThanOrEqualTo(18),
      );
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
        'AI-UAT-稳定表单',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
