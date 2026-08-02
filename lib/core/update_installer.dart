import 'package:http/http.dart' as http;

import 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart';

/// True when the current platform can install an APK from a local file
/// (Android only).
bool get canInstallApkLocally => canInstallApkLocallyImpl;

/// Downloads [url] into the app documents directory and returns the absolute
/// local path, or null when the download failed or the platform cannot
/// persist files (web).
Future<String?> downloadUpdateFile(
  String url, {
  http.Client? client,
  Future<String> Function()? directoryProvider,
  void Function(int received, int? total)? onProgress,
}) {
  return downloadUpdateFileImpl(
    url,
    client: client,
    directoryProvider: directoryProvider,
    onProgress: onProgress,
  );
}

/// Opens a downloaded APK with the system package installer on Android.
/// Returns false on platforms without an installer.
Future<bool> openApkInstaller(String path) => openApkInstallerImpl(path);
