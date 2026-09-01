import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../storage/secure_session_store.dart';

final mobileDeviceIdentityProvider = Provider<MobileDeviceIdentityService>(
  (ref) => MobileDeviceIdentityService(ref.read(secureSessionStoreProvider)),
);

final class MobileDeviceIdentity {
  const MobileDeviceIdentity({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.operatingSystem,
    required this.clientVersion,
  });

  final String id;
  final String name;
  final String fingerprint;
  final String operatingSystem;
  final String clientVersion;
}

final class MobileDeviceIdentityService {
  MobileDeviceIdentityService(this._store);

  final SecureSessionStore _store;
  Future<MobileDeviceIdentity>? _cached;

  Future<MobileDeviceIdentity> resolve() => _cached ??= _resolve();

  Future<MobileDeviceIdentity> _resolve() async {
    final existingId = await _store.readDeviceId();
    final id = existingId?.isNotEmpty == true ? existingId! : const Uuid().v4();
    if (existingId == null || existingId.isEmpty) {
      await _store.saveDeviceId(id);
    }
    final package = await PackageInfo.fromPlatform();
    if (kIsWeb) {
      return MobileDeviceIdentity(
        id: id,
        name: 'Web 预览终端',
        fingerprint: sha256.convert(utf8.encode('mobile-web|$id')).toString(),
        operatingSystem: 'Web',
        clientVersion: package.version,
      );
    }

    var name = '移动终端';
    var fingerprintSource = 'mobile|$id';
    var operatingSystem = Platform.operatingSystem;
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final value = await info.androidInfo;
      name = '${value.brand} ${value.model}'.trim();
      fingerprintSource =
          'mobile|${value.id}|${value.brand}|${value.model}|$id';
      operatingSystem = 'Android ${value.version.release}';
    } else if (Platform.isIOS) {
      final value = await info.iosInfo;
      name = value.name;
      fingerprintSource =
          'mobile|${value.identifierForVendor}|${value.utsname.machine}|$id';
      operatingSystem = '${value.systemName} ${value.systemVersion}';
    }
    return MobileDeviceIdentity(
      id: id,
      name: name,
      fingerprint: sha256.convert(utf8.encode(fingerprintSource)).toString(),
      operatingSystem: operatingSystem,
      clientVersion: package.version,
    );
  }
}
