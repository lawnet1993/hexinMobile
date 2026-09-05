import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/shared/widgets/visible_refresh_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  testWidgets('visible refresh stops offstage and resumes once on return', (
    tester,
  ) async {
    var calls = 0;
    final scheduler = VisibleRefreshScheduler(() async {
      calls++;
    });
    addTearDown(scheduler.dispose);
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 0);
    scheduler.setVisible(true);
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    scheduler.setVisible(false);
    await tester.pump(const Duration(seconds: 90));
    expect(calls, 2);
    scheduler.setVisible(true);
    await tester.pump();
    expect(calls, 3);
    scheduler.dispose();
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 3);
  });

  testWidgets(
    'background polling stops and foreground resumes without overlap',
    (tester) async {
      var calls = 0;
      final pending = Completer<void>();
      final scheduler = VisibleRefreshScheduler(() async {
        calls++;
        if (calls == 1) await pending.future;
      });
      addTearDown(scheduler.dispose);
      scheduler.setVisible(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 90));
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete();
      await tester.pump(const Duration(seconds: 90));
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 2);
      scheduler.dispose();
    },
  );

  testWidgets('failed refresh retries only on the next visible tick', (
    tester,
  ) async {
    var calls = 0;
    final scheduler = VisibleRefreshScheduler(() async {
      calls++;
      throw StateError('offline');
    });
    addTearDown(scheduler.dispose);
    scheduler.setVisible(true);
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    scheduler.dispose();
    expect(tester.takeException(), isNull);
  });
}
