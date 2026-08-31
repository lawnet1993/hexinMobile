import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSize = 120
    ..maximumSizeBytes = 48 * 1024 * 1024;
  SecureTunnel.registerWith();
  runApp(const ProviderScope(child: HexingMobileApp()));
}
