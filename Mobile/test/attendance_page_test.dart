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

    expect(find.text('今日打卡已完成'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.byKey(const Key('attendance-final-status')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('attendance-final-status'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('attendance-punch-summary'))).height,
      lessThanOrEqualTo(120),
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('notification target brings its attendance exception first', (
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
              punchMessage: '',
              monthExceptionCount: 2,
              requirePunchCorrectionApproval: true,
              monthlyPunchCorrectionLimit: 3,
              monthPunchCorrectionCount: 0,
              exceptions: [
                OaAttendanceException(
                  id: 'exception-latest',
                  workDate: '2026-08-31',
                  type: 'missing_check_in',
                  status: 'pending',
                  resolutionApprovalRequestId: null,
                ),
                OaAttendanceException(
                  id: 'exception-target',
                  workDate: '2026-08-14',
                  type: 'missing_check_in',
                  status: 'pending',
                  resolutionApprovalRequestId: null,
                ),
              ],
              recentRecords: [],
            ),
          ),
        ],
        child: const MaterialApp(
          home: AttendancePage(
            correctionMode: true,
            initialExceptionId: 'exception-target',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(
      const ValueKey('attendance-exception-exception-target'),
    );
    final latest = find.byKey(
      const ValueKey('attendance-exception-exception-latest'),
    );
    expect(target, findsOneWidget);
    expect(
      tester.getTopLeft(target).dy,
      lessThan(tester.getTopLeft(latest).dy),
    );
    final targetContainer = tester.widget<Container>(target);
    final decoration = targetContainer.decoration! as BoxDecoration;
    expect(decoration.color, isNot(Colors.transparent));
  });
}
