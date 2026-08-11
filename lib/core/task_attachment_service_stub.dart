Future<String?> storeTaskAttachmentBytes({
  required String displayName,
  required List<int> bytes,
}) async {
  return null;
}

Future<List<int>?> readStoredTaskAttachmentBytesPlatform(
  String path, {
  int maxBytes = 10 * 1024 * 1024,
}) async {
  return null;
}

Future<bool> openStoredTaskAttachment(String path) async {
  return false;
}
