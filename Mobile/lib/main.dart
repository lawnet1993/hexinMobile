import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SecureTunnel.registerWith();
  runApp(const ProviderScope(child: HexingMobileApp()));
}
