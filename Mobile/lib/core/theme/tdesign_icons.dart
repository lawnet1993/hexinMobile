import 'package:flutter/widgets.dart';

/// TDesign's official icon font exposed as plain [IconData] constants.
///
/// The published TDesign Flutter 0.2.7 package subclasses [IconData], which is
/// no longer supported by the Flutter version used by this project. Keeping the
/// official font locally preserves the visual language without coupling the app
/// to that incompatible implementation.
abstract final class TDIcons {
  static const _family = 'TDIcons';

  static const appFilled = IconData(0xE026, fontFamily: _family);
  static const app = IconData(0xE027, fontFamily: _family);
  static const calendarEdit = IconData(0xE0E5, fontFamily: _family);
  static const calendarEvent = IconData(0xE0E7, fontFamily: _family);
  static const cart = IconData(0xE113, fontFamily: _family);
  static const chatMessageFilled = IconData(0xE177, fontFamily: _family);
  static const chatMessage = IconData(0xE178, fontFamily: _family);
  static const chevronRight = IconData(0xE1A1, fontFamily: _family);
  static const cloud = IconData(0xE1EF, fontFamily: _family);
  static const file1 = IconData(0xE2DA, fontFamily: _family);
  static const fileSafety = IconData(0xE309, fontFamily: _family);
  static const filter = IconData(0xE332, fontFamily: _family);
  static const money = IconData(0xE543, fontFamily: _family);
  static const notification = IconData(0xE579, fontFamily: _family);
  static const sound = IconData(0xE6A7, fontFamily: _family);
  static const taskChecked = IconData(0xE715, fontFamily: _family);
  static const time = IconData(0xE754, fontFamily: _family);
  static const userFilled = IconData(0xE7C3, fontFamily: _family);
  static const userTime = IconData(0xE7DB, fontFamily: _family);
  static const user = IconData(0xE7E6, fontFamily: _family);
  static const usergroupFilled = IconData(0xE7EF, fontFamily: _family);
  static const usergroup = IconData(0xE7F0, fontFamily: _family);
  static const work = IconData(0xE83C, fontFamily: _family);
}
