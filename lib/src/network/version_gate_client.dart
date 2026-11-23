import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:http/http.dart' as http;

import '../controller/upgate_controller.dart';
import '../domain/update_manifest.dart';
import '../utils/platform_info.dart';

/// Callback invoked when the server responds with an update enforcement signal
/// (for example HTTP `426 Upgrade Required`).
typedef VersionGateCallback = void Function(
  int statusCode,
  Map<String, String> headers,
);

/// An [http.BaseClient] wrapper that awaits and caches the installed
/// `version+build` on the first request, injects `X-App-*` headers, and
/// triggers upgrade callbacks on HTTP `426 Upgrade Required`.
class VersionGateHttpClient extends http.BaseClient {
  /// Creates a [VersionGateHttpClient] wrapping [inner].
  VersionGateHttpClient({
    http.Client? inner,
    this.appCode,
    this.appVersion,
    this.fallbackVersion = '1.0.0+1',
    this.platform,
    this.architecture,
    Future<String> Function()? versionResolver,
    this.controller,
    this.onUpgradeRequired,
    this.onGateTriggered,
  })  : _inner = inner ?? http.Client(),
        _versionResolver = versionResolver;

  final http.Client _inner;
  final Future<String> Function()? _versionResolver;

  /// Optional application identifier sent in `X-App-Code`.
  final String? appCode;

  /// Optional explicit semantic version string sent in `X-App-Version`.
  final String? appVersion;

  /// Fallback version used when runtime package info is unavailable.
  final String fallbackVersion;

  /// Optional platform identifier sent in `X-Platform`.
  final String? platform;

  /// Optional CPU architecture identifier sent in `X-App-Arch`.
  final String? architecture;

  /// Optional [UpgateController] notified on HTTP `426 Upgrade Required`.
  final UpgateController? controller;

  /// Optional callback invoked when the server responds with HTTP `426`.
  final VoidCallback? onUpgradeRequired;

  /// Optional detailed callback invoked when a response triggers a version gate.
  final VersionGateCallback? onGateTriggered;

  String? _cachedVersion;
  Future<String>? _inFlightVersionLookup;

  Future<String> _resolveVersion() {
    final explicit = appVersion?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return Future.value(explicit);
    }
    if (_cachedVersion != null && _cachedVersion!.isNotEmpty) {
      return Future.value(_cachedVersion!);
    }
    return _inFlightVersionLookup ??= () async {
      final resolver = _versionResolver ??
          () => PlatformInfo.resolveInstalledVersion(fallbackVersion);
      final resolved = await resolver();
      _cachedVersion = resolved;
      return resolved;
    }();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final resolvedVersion = await _resolveVersion();
    final effectivePlatform =
        platform ?? (Upgate.isInitialized ? Upgate.instance.config.resolvedPlatform : PlatformInfo.detectPlatformName());
    final effectiveArch =
        architecture ?? (Upgate.isInitialized ? Upgate.instance.config.resolvedArchitecture : PlatformInfo.detectArchitecture());
    final effectiveAppCode =
        appCode ?? (Upgate.isInitialized ? Upgate.instance.config.appCode : null);

    if (effectiveAppCode != null && effectiveAppCode.isNotEmpty) {
      request.headers.putIfAbsent('X-App-Code', () => effectiveAppCode);
    }
    request.headers.putIfAbsent('X-Platform', () => effectivePlatform);
    request.headers.putIfAbsent('X-App-Arch', () => effectiveArch);
    request.headers.putIfAbsent('X-App-Version', () => resolvedVersion);

    final response = await _inner.send(request);

    if (response.statusCode == 426) {
      onGateTriggered?.call(response.statusCode, response.headers);
      onUpgradeRequired?.call();
      final activeController =
          controller ?? (Upgate.isInitialized ? Upgate.instance : null);
      if (activeController != null) {
        // Read body to parse V2 manifest if provided by 426 Upgrade Required
        final bodyBytes = await response.stream.toBytes();
        try {
          final bodyStr = utf8.decode(bodyBytes);
          final json = jsonDecode(bodyStr);
          if (json is Map<String, dynamic>) {
            final manifest = UpdateManifest.fromJson(json, _cachedVersion ?? fallbackVersion);
            activeController.setManifest(manifest);
          } else {
            activeController.checkForUpdate(force: true);
          }
        } catch (_) {
          activeController.checkForUpdate(force: true);
        }
        return http.StreamedResponse(
          Stream.fromIterable([bodyBytes]),
          response.statusCode,
          contentLength: bodyBytes.length,
          request: response.request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      }
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
