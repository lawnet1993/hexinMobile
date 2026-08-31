import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

import 'artifact_signature_verifier.dart';
import 'mobile_artifact.dart';

final class MobileArtifactStore {
  const MobileArtifactStore({
    required Dio downloadClient,
    required ArtifactSignatureVerifier signatureVerifier,
    required Directory root,
  }) : this._(downloadClient, signatureVerifier, root);

  const MobileArtifactStore._(
    this._downloadClient,
    this._signatureVerifier,
    this._root,
  );

  final Dio _downloadClient;
  final ArtifactSignatureVerifier _signatureVerifier;
  final Directory _root;

  Future<MobileArtifactRelease> install(MobileArtifactManifest manifest) async {
    await _signatureVerifier.verify(manifest);
    final bytes = await _download(manifest);
    _verifyBytes(manifest, bytes);

    final kindDirectory = await _kindDirectory(manifest.kind)
        .create(recursive: true);
    final releaseDirectory = Directory(
      path.join(
        kindDirectory.path,
        _safeName('${manifest.version}-${manifest.id}'),
      ),
    );
    await releaseDirectory.create(recursive: true);
    final artifactFile = File(path.join(releaseDirectory.path, 'artifact.bin'));
    final manifestFile = File(
      path.join(releaseDirectory.path, 'manifest.json'),
    );
    await artifactFile.writeAsBytes(bytes, flush: true);
    await manifestFile.writeAsString(
      jsonEncode(manifest.toJson()),
      flush: true,
    );

    final currentFile = _currentFile(manifest.kind);
    final previousFile = _previousFile(manifest.kind);
    if (await currentFile.exists()) {
      await previousFile.writeAsString(
        await currentFile.readAsString(),
        flush: true,
      );
    }
    final pointer = _Pointer(
      manifest: manifest,
      filePath: artifactFile.path,
      manifestPath: manifestFile.path,
    );
    await currentFile.writeAsString(jsonEncode(pointer.toJson()), flush: true);
    return MobileArtifactRelease(
      manifest: manifest,
      filePath: artifactFile.path,
    );
  }

  Future<MobileArtifactRelease?> current(MobileArtifactKind kind) async {
    final pointer = await _readPointer(_currentFile(kind));
    if (pointer == null) return null;
    try {
      await _verifyInstalled(pointer);
      return MobileArtifactRelease(
        manifest: pointer.manifest,
        filePath: pointer.filePath,
      );
    } on ArtifactVerificationException {
      return rollback(kind);
    } on FileSystemException {
      return rollback(kind);
    } on FormatException {
      return rollback(kind);
    }
  }

  Future<MobileArtifactRelease> rollback(MobileArtifactKind kind) async {
    final previous = await _readPointer(_previousFile(kind));
    if (previous == null) {
      throw const ArtifactVerificationException('没有可回滚的移动端制品版本。');
    }
    await _verifyInstalled(previous);
    await _currentFile(kind)
        .writeAsString(jsonEncode(previous.toJson()), flush: true);
    return MobileArtifactRelease(
      manifest: previous.manifest,
      filePath: previous.filePath,
    );
  }

  Future<List<int>> _download(MobileArtifactManifest manifest) async {
    final response = await _downloadClient.get<List<int>>(
      manifest.url,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }

  Future<void> _verifyInstalled(_Pointer pointer) async {
    await _signatureVerifier.verify(pointer.manifest);
    final bytes = await File(pointer.filePath).readAsBytes();
    _verifyBytes(pointer.manifest, bytes);
  }

  void _verifyBytes(MobileArtifactManifest manifest, List<int> bytes) {
    if (bytes.length != manifest.size) {
      throw ArtifactVerificationException(
        '制品大小不匹配：期望 ${manifest.size}，实际 ${bytes.length}。',
      );
    }
    final digest = sha256.convert(bytes).toString();
    if (digest != manifest.sha256) {
      throw const ArtifactVerificationException('制品 SHA-256 校验失败。');
    }
  }

  Future<_Pointer?> _readPointer(File file) async {
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) {
      throw const FormatException('Artifact pointer is invalid.');
    }
    return _Pointer.fromJson(json.cast<String, Object?>());
  }

  Directory _kindDirectory(MobileArtifactKind kind) =>
      Directory(path.join(_root.path, kind.wireName));

  File _currentFile(MobileArtifactKind kind) =>
      File(path.join(_root.path, kind.wireName, 'current.json'));

  File _previousFile(MobileArtifactKind kind) =>
      File(path.join(_root.path, kind.wireName, 'previous.json'));

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

final class _Pointer {
  const _Pointer({
    required this.manifest,
    required this.filePath,
    required this.manifestPath,
  });

  factory _Pointer.fromJson(Map<String, Object?> json) {
    final manifestJson = json['manifest'];
    if (manifestJson is! Map) {
      throw const FormatException('Artifact pointer manifest is invalid.');
    }
    return _Pointer(
      manifest: MobileArtifactManifest.fromJson(
        manifestJson.cast<String, Object?>(),
      ),
      filePath: json['filePath']?.toString() ?? '',
      manifestPath: json['manifestPath']?.toString() ?? '',
    );
  }

  final MobileArtifactManifest manifest;
  final String filePath;
  final String manifestPath;

  Map<String, Object?> toJson() => {
    'manifest': manifest.toJson(),
    'filePath': filePath,
    'manifestPath': manifestPath,
  };
}
