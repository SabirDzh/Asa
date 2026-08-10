import 'package:http/http.dart' as http;

bool get canInstallApkLocallyImpl => false;

Future<String?> downloadUpdateFileImpl(
  String url, {
  http.Client? client,
  Future<String> Function()? directoryProvider,
  void Function(int received, int? total)? onProgress,
  String? expectedSha256,
}) async {
  return null;
}

Future<bool> openApkInstallerImpl(String path) async => false;
