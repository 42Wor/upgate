/// Fallback platform name when neither `dart:io` nor `dart:js_interop` is active.
String detectPlatformName() => 'unknown';

/// Fallback architecture when neither `dart:io` nor `dart:js_interop` is active.
String detectArchitecture() => 'universal';
