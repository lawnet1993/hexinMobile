import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/artifacts/artifact_signature_verifier.dart';
import 'package:hexing_terminal_mobile/core/artifacts/mobile_artifact.dart';
import 'package:hexing_terminal_mobile/core/artifacts/mobile_artifact_store.dart';

void main() {
  late Directory root;
  late Directory source;
  late HttpServer server;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('artifact-store-');
    source = await Directory.systemTemp.createTemp('artifact-source-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      final file = File('${source.path}/$name');
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        await request.response.addStream(file.openRead());
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
    if (await source.exists()) await source.delete(recursive: true);
    await server.close(force: true);
  });

  test('verified releases promote atomically and roll back', () async {
    final verifier = _AcceptingVerifier();
    final store = MobileArtifactStore(
      downloadClient: Dio(),
      signatureVerifier: verifier,
      root: root,
    );
    final first = await _sourceManifest(source, server.port, '1.0.0', 'first');
    final second = await _sourceManifest(
      source,
      server.port,
      '1.1.0',
      'second',
    );

    await store.install(first);
    await store.install(second);
    expect((await store.current(first.kind))?.manifest.version, '1.1.0');

    final rolledBack = await store.rollback(first.kind);
    expect(rolledBack.manifest.version, '1.0.0');
    expect((await store.current(first.kind))?.manifest.version, '1.0.0');
    // Install, current-read and rollback boundaries all verify signatures.
    expect(verifier.calls, 5);
  });

  test('hash mismatch never replaces the current release', () async {
    final store = MobileArtifactStore(
      downloadClient: Dio(),
      signatureVerifier: _AcceptingVerifier(),
      root: root,
    );
    final good = await _sourceManifest(source, server.port, '1.0.0', 'good');
    await store.install(good);
    final bad = await _sourceManifest(source, server.port, '2.0.0', 'bad');
    final tampered = MobileArtifactManifest.fromJson({
      ...bad.toJson(),
      'sha256': List.filled(64, '0').join(),
    });

    await expectLater(
      store.install(tampered),
      throwsA(isA<ArtifactVerificationException>()),
    );
    expect((await store.current(good.kind))?.manifest.version, '1.0.0');
  });

  test('corrupted current release automatically rolls back', () async {
    final store = MobileArtifactStore(
      downloadClient: Dio(),
      signatureVerifier: _AcceptingVerifier(),
      root: root,
    );
    final first = await _sourceManifest(source, server.port, '1.0.0', 'first');
    final second = await _sourceManifest(
      source,
      server.port,
      '1.1.0',
      'second',
    );
    await store.install(first);
    final installed = await store.install(second);
    await File(installed.filePath).writeAsString('corrupted', flush: true);

    final recovered = await store.current(second.kind);

    expect(recovered?.manifest.version, '1.0.0');
    expect(await File(recovered!.filePath).readAsString(), 'first');
  });

  test('non TLS remote package URL is rejected', () {
    final json = <String, Object?>{
      ...(MobileArtifactManifest(
        id: 'unsafe',
        kind: MobileArtifactKind.managedBrowser,
        version: '1.0.0',
        platform: 'android',
        architecture: 'arm64-v8a',
        url: 'https://packages.example.com/browser.zip',
        sha256: List.filled(64, 'a').join(),
        size: 1,
        signature: 'signature',
        signatureAlgorithm: 'ed25519',
        keyId: 'test',
        publishedAt: DateTime.utc(2026, 8, 14),
      )).toJson(),
      'url': 'http://packages.example.com/browser.zip',
    };

    expect(
      () => MobileArtifactManifest.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<MobileArtifactManifest> _sourceManifest(
  Directory source,
  int port,
  String version,
  String content,
) async {
  final file = File('${source.path}/$version.bin');
  final bytes = utf8.encode(content);
  await file.writeAsBytes(bytes);
  return MobileArtifactManifest(
    id: version,
    kind: MobileArtifactKind.configuration,
    version: version,
    platform: 'android',
    architecture: 'arm64-v8a',
    url: 'http://127.0.0.1:$port/$version.bin',
    sha256: sha256.convert(bytes).toString(),
    size: bytes.length,
    signature: 'test-signature',
    signatureAlgorithm: 'ed25519',
    keyId: 'test',
    publishedAt: DateTime.utc(2026, 8, 14),
  );
}

final class _AcceptingVerifier implements ArtifactSignatureVerifier {
  int calls = 0;
  @override
  Future<void> verify(MobileArtifactManifest manifest) async {
    calls++;
  }
}
