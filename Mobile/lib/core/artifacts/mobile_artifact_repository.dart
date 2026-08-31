import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import '../config/app_environment.dart';
import '../network/api_client.dart';
import 'artifact_signature_verifier.dart';
import 'mobile_artifact.dart';
import 'mobile_artifact_store.dart';

final mobileArtifactStoreProvider = FutureProvider<MobileArtifactStore>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  final root = Directory('${support.path}/mobile-artifacts');
  return MobileArtifactStore(
    downloadClient: Dio(),
    signatureVerifier: Ed25519ArtifactSignatureVerifier(
      AppEnvironment.mobileArtifactPublicKeys,
    ),
    root: root,
  );
});

final managedBrowserSyncProvider =
    AsyncNotifierProvider<ManagedBrowserSyncController, MobileArtifactRelease?>(
      ManagedBrowserSyncController.new,
    );

class ManagedBrowserSyncController
    extends AsyncNotifier<MobileArtifactRelease?> {
  @override
  Future<MobileArtifactRelease?> build() async {
    final store = await ref.watch(mobileArtifactStoreProvider.future);
    return store.current(MobileArtifactKind.managedBrowser);
  }

  Future<void> synchronize({
    required String deviceId,
    required TunnelRuntimeIdentity runtime,
  }) async {
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, Object?>>(
        '/api/client/mobile-artifacts/managed-browser/current',
        queryParameters: <String, Object?>{
          'deviceId': deviceId,
          'platform': runtime.platform,
          'architecture': runtime.architecture,
          'coreVersion': runtime.coreVersion,
          'channel': AppEnvironment.channel,
        },
        options: Options(contentType: Headers.jsonContentType),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return;
      final manifest = MobileArtifactManifest.fromJson(body);
      final store = await ref.read(mobileArtifactStoreProvider.future);
      state = AsyncData(await store.install(manifest));
    } catch (error, stackTrace) {
      final current = state.value;
      if (current == null) {
        state = AsyncError(error, stackTrace);
      }
    }
  }
}
