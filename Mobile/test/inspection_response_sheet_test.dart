import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/attendance/presentation/inspection_response_sheet.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  testWidgets('在岗确认使用移动端底部抽屉', (tester) async {
    String? selectedStatus;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  selectedStatus = await showInspectionResponseSheet(
                    context,
                    const OaActiveInspection(
                      inspectionId: 'inspection-1',
                      title: '在岗确认',
                      message: '请确认当前在岗状态。',
                      openedAt: null,
                      responseStatus: 'pending',
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('在岗确认'), findsOneWidget);
    expect(find.text('请确认当前在岗状态。'), findsOneWidget);
    expect(find.text('确认在岗'), findsOneWidget);
    expect(find.text('暂时无法响应'), findsOneWidget);

    await tester.tap(find.text('确认在岗'));
    await tester.pumpAndSettle();
    expect(selectedStatus, 'present');
  });
}
