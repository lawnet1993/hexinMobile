import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android native push gate admits the controlled friend-request route',
    () {
      final source = File(
        'android/app/src/main/kotlin/com/hexing/zhilian/'
        'hexing_terminal_mobile/MainActivity.kt',
      ).readAsStringSync();

      expect(source, contains('route == "/contacts"'));
      expect(source, contains('route == "/contacts?mode=requests"'));
      expect(source, contains('CHAT_ROUTE.matches(it)'));
      expect(source, contains('APPROVAL_ROUTE.matches(it)'));
      expect(source, contains('if (sink == null)'));
      expect(source, contains('initialTargetRoute = route'));
    },
  );
}
