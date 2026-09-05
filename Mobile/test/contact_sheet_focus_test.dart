import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';

void main() {
  for (final action in ['添加好友', '选择部门']) {
    testWidgets('$action closing does not reopen the parent search keyboard', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imBootstrapProvider.overrideWith(
              (_) async => PreviewData.imBootstrap,
            ),
            imDepartmentsProvider.overrideWith(
              (_) async => const [
                ImDepartment(
                  id: 'fixture-dept',
                  name: 'Fixture department',
                  code: 'UAT',
                  parentId: '',
                  sortOrder: 0,
                ),
              ],
            ),
            pendingFriendApplicationsProvider.overrideWith(
              (_) async => const [],
            ),
            contactPresenceRefresherProvider.overrideWithValue(() async {}),
          ],
          child: const MaterialApp(home: ContactsPage()),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byKey(const Key('contacts-search-field')),
        matching: find.byType(TextField),
      );
      await tester.showKeyboard(search);
      await tester.enterText(search, 'fixture');
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.tap(find.byTooltip(action));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(editable.controller.text, 'fixture');
      expect(editable.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
