import 'dart:io' show Platform;

/// Detects the current native OS name.
String detectPlatformName() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

/// Detects the host CPU architecture from `Platform.version`.
String detectArchitecture() {
  final v = Platform.version.toLowerCase();
  if (v.contains('arm64') || v.contains('aarch64')) {
    return Platform.isAndroid ? 'arm64-v8a' : 'arm64';
  }
  if (v.contains('x64') || v.contains('x86_64') || v.contains('amd64')) {
    return 'x64';
  }
  if (v.contains('ia32') || v.contains('x86')) {
    return 'x86';
  }
  return 'universal';
}
