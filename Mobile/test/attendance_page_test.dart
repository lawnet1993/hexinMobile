import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/attendance/presentation/attendance_page.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  testWidgets('completed attendance uses a final compact state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          oaAttendanceOverviewProvider.overrideWith(
            (ref) async => const OaAttendanceOverview(
              today: null,
              nextPunchType: 'check_in',
              canPunch: false,
              punchMessage: '今日打卡已完成',
              monthExceptionCount: 0,
              requirePunchCorrectionApproval: true,
              monthlyPunchCorrectionLimit: 3,
              monthPunchCorrectionCount: 0,
              exceptions: [],
              recentRecords: [],
            ),
          ),
          oaBehaviorDefinitionsProvider.overrideWith((ref) async => const []),
          oaActiveBehaviorSessionsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: const MaterialApp(home: AttendancePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('今日打卡已完成'), findsWidgets);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '今日打卡已完成'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '今日打卡已完成'))
          .onPressed,
      isNull,
    );
  });
}
