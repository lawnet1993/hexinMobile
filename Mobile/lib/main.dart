import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/diagnostics/mobile_startup_diagnostics.dart';
import 'core/media/mobile_image_compressor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startup = MobileStartupDiagnostics.install();
  final imageCacheCleanupCutoff = DateTime.now();
  PaintingBinding.instance.imageCache
    ..maximumSize = 120
    ..maximumSizeBytes = 48 * 1024 * 1024;
  runApp(const ProviderScope(child: HexingMobileApp()));
  startup?.mark(MobileStartupStage.runAppReturned);
  unawaited(
    deleteIncompleteMobileImageSources(
      // Some mobile filesystems expose coarse modification timestamps. This
      // grace window prevents the asynchronous sweep from deleting a source
      // directory created by the current process.
      createdBefore: imageCacheCleanupCutoff.subtract(
        const Duration(minutes: 1),
      ),
    ),
  );
}
