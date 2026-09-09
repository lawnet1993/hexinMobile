String devicePlatformLabel(String value) =>
    switch (value.trim().toLowerCase()) {
      'android' => 'Android',
      'ios' => 'iOS',
      'windows' => 'Windows',
      'macos' || 'mac' => 'macOS',
      'linux' => 'Linux',
      _ => value.trim(),
    };

String deviceDisplayName({required String name, required String platform}) {
  final rawName = name.trim();
  final rawPlatform = platform.trim();
  final platformLabel = devicePlatformLabel(rawPlatform);
  if (rawName.isEmpty) {
    return platformLabel.isEmpty ? '未知设备' : '$platformLabel 设备';
  }
  final normalizedName = rawName.toLowerCase();
  final genericNames = <String>{
    if (rawPlatform.isNotEmpty) '${rawPlatform.toLowerCase()} device',
    if (platformLabel.isNotEmpty) '${platformLabel.toLowerCase()} device',
  };
  if (genericNames.contains(normalizedName)) return '$platformLabel 设备';
  return rawName;
}

bool deviceNameIncludesPlatform({
  required String displayName,
  required String platform,
}) {
  final label = devicePlatformLabel(platform).toLowerCase();
  return label.isNotEmpty && displayName.toLowerCase().contains(label);
}

String deviceCompactLabel({required String name, required String platform}) {
  final displayName = deviceDisplayName(name: name, platform: platform);
  final platformLabel = devicePlatformLabel(platform);
  if (platformLabel.isEmpty ||
      deviceNameIncludesPlatform(
        displayName: displayName,
        platform: platform,
      )) {
    return displayName;
  }
  return '$displayName · $platformLabel';
}
