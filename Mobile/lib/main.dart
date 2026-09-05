import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import 'app.dart';
import 'core/diagnostics/mobile_startup_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startup = MobileStartupDiagnostics.install();
  PaintingBinding.instance.imageCache
    ..maximumSize = 120
    ..maximumSizeBytes = 48 * 1024 * 1024;
  SecureTunnel.registerWith();
  startup?.mark(MobileStartupStage.tunnelRegistered);
  runApp(const ProviderScope(child: HexingMobileApp()));
  startup?.mark(MobileStartupStage.runAppReturned);
}
