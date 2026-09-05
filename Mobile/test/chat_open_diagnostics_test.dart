import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/diagnostics/chat_open_diagnostics.dart';

void main() {
  test('invalid snapshot time cannot set a cache hit or message count', () {
    final sample = ChatOpenMeasurement()
      ..mark(ChatOpenStage.routeMounted, 100)
      ..snapshot(cached: true, count: 10, at: 50);
    expect(sample.summary()['cacheHit'], isNull);
    expect(sample.summary()['messageCount'], isNull);
  });
  test('non-profile builds never begin or attach a trace', () {
    expect(ChatOpenDiagnostics.begin(), isNull);
    expect(ChatOpenDiagnostics.attach('private-route-key'), isNull);
  });
  test('missing checkpoints remain absent rather than zero latency', () {
    expect(ChatOpenMeasurement().summary(), {
      'cacheHit': null,
      'messageCount': null,
      'stagesMicros': {'tap': 0},
    });
  });
  test('first timing is retained across rebuilds and duplicate callbacks', () {
    final sample = ChatOpenMeasurement()
      ..mark(ChatOpenStage.keyboardHidden, 100)
      ..mark(ChatOpenStage.keyboardHidden, 999)
      ..mark(ChatOpenStage.routeMounted, 200)
      ..mark(ChatOpenStage.routeFrame, 300);
    expect(sample.summary()['stagesMicros'], {
      'tap': 0,
      'keyboardHidden': 100,
      'routeMounted': 200,
      'routeFrame': 300,
    });
  });
  test(
    'negative and regressing elapsed values cannot fabricate a checkpoint',
    () {
      final sample = ChatOpenMeasurement()
        ..mark(ChatOpenStage.keyboardHidden, -1)
        ..mark(ChatOpenStage.routeMounted, 100)
        ..mark(ChatOpenStage.routeFrame, 50);
      expect(sample.summary()['stagesMicros'], {'tap': 0, 'routeMounted': 100});
    },
  );
  test(
    'first message snapshot records hot cache separately from rendering',
    () {
      final sample = ChatOpenMeasurement()
        ..snapshot(cached: true, count: 80, at: 100)
        ..snapshot(cached: false, count: 81, at: 200);
      expect(sample.summary()['cacheHit'], isTrue);
      expect(sample.summary()['messageCount'], 80);
      expect(sample.summary()['stagesMicros'], {
        'tap': 0,
        'messagesAvailable': 100,
      });
    },
  );
  test('empty conversation is available but not a laid out latest message', () {
    final sample = ChatOpenMeasurement()
      ..snapshot(cached: false, count: 0, at: 100);
    expect(sample.summary()['messageCount'], 0);
    expect(
      (sample.summary()['stagesMicros'] as Map).containsKey(
        'latestMessageLaidOut',
      ),
      isFalse,
    );
  });
  test('invalid counts do not replace a later valid snapshot', () {
    final sample = ChatOpenMeasurement()
      ..snapshot(cached: true, count: -1, at: 100)
      ..snapshot(cached: false, count: 5, at: 200);
    expect(sample.summary()['cacheHit'], isFalse);
    expect(sample.summary()['messageCount'], 5);
  });
}
