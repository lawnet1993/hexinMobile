import 'package:intl/intl.dart';

String compactListDateTimeLabel(DateTime? value, {DateTime? now}) {
  if (value == null) return '';
  final localValue = value.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final valueDate = DateTime(localValue.year, localValue.month, localValue.day);
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final dayDifference = today.difference(valueDate).inDays;
  if (dayDifference == 0) return DateFormat('HH:mm').format(localValue);
  if (dayDifference == 1) return '昨天';

  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (!valueDate.isBefore(weekStart) && valueDate.isBefore(today)) {
    return const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][localValue.weekday -
        1];
  }
  return DateFormat(localValue.year == localNow.year ? 'MM/dd' : 'yyyy/MM/dd')
      .format(localValue);
}
