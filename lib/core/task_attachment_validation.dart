const int kMaxTaskAttachmentNameLength = 128;
const int kMaxTaskLinkLength = 2048;

String? normalizeTaskAttachmentLink(String value) {
  final candidate = value.trim();
  if (candidate.isEmpty || candidate.length > kMaxTaskLinkLength) return null;
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(candidate)) return null;

  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;

  return uri.replace(scheme: scheme, host: uri.host.toLowerCase()).toString();
}

String attachmentDisplayName(String name) {
  final basename = name.trim().split(RegExp(r'[\\/]')).last;
  final safeName = basename.isEmpty ? 'attachment' : basename;
  if (safeName.length <= kMaxTaskAttachmentNameLength) return safeName;
  return safeName.substring(0, kMaxTaskAttachmentNameLength);
}

bool isSafeStoredTaskAttachmentValue(String value) {
  final candidate = value.trim();
  if (candidate.isEmpty || RegExp(r'[\x00-\x1F\x7F]').hasMatch(candidate)) {
    return false;
  }
  final segments = candidate.split(RegExp(r'[\\/]'));
  return !segments.contains('..') && segments.contains('task_attachments');
}

String sanitizeTaskDescription(String value) {
  final withoutControls = value.replaceAll(
    RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
    '',
  );
  // Descriptions are rendered by Flutter's plain Text widget, never as HTML.
  // Keep markup characters literal so user content cannot become executable.
  return withoutControls.trim();
}

String taskAttachmentExtension(String name) {
  final basename = attachmentDisplayName(name).toLowerCase();
  final dot = basename.lastIndexOf('.');
  if (dot <= 0 || dot == basename.length - 1) return '';
  return basename.substring(dot + 1);
}

String? taskAttachmentMimeForName(String name) {
  switch (taskAttachmentExtension(name)) {
    case 'pdf':
      return 'application/pdf';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'zip':
      return 'application/zip';
    case 'txt':
    case 'log':
      return 'text/plain';
    case 'md':
      return 'text/markdown';
    case 'csv':
      return 'text/csv';
    case 'json':
      return 'application/json';
    case 'xml':
      return 'application/xml';
    case 'webp':
      return 'image/webp';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    default:
      return null;
  }
}

bool isSafeTaskAttachmentMetadata(String name, String? mimeType) {
  final extension = taskAttachmentExtension(name);
  const supported = {
    'pdf',
    'docx',
    'xlsx',
    'pptx',
    'zip',
    'txt',
    'md',
    'csv',
    'json',
    'xml',
    'log',
    'webp',
    'jpg',
    'jpeg',
    'png',
    'gif',
  };
  if (!supported.contains(extension)) return false;

  final mime = mimeType?.trim().toLowerCase();
  if (mime == null || mime.isEmpty) return true;
  if (mime == 'image/*') {
    return const {'webp', 'jpg', 'jpeg', 'png', 'gif'}.contains(extension);
  }
  if (extension == 'pdf') return mime == 'application/pdf';
  if (extension == 'webp') return mime == 'image/webp';
  if (extension == 'jpg' || extension == 'jpeg') return mime == 'image/jpeg';
  if (extension == 'png') return mime == 'image/png';
  if (extension == 'gif') return mime == 'image/gif';
  if (extension == 'txt' || extension == 'md' || extension == 'log') {
    return mime == 'text/plain' || mime == 'text/markdown';
  }
  if (extension == 'csv') return mime == 'text/csv' || mime == 'text/plain';
  if (extension == 'json') {
    return mime == 'application/json' || mime == 'text/plain';
  }
  if (extension == 'xml') {
    return mime == 'application/xml' ||
        mime == 'text/xml' ||
        mime == 'text/plain';
  }
  if (extension == 'zip') {
    return mime == 'application/zip' || mime == 'application/x-zip-compressed';
  }
  return mime == 'application/zip' ||
      mime.startsWith('application/vnd.openxmlformats-officedocument.');
}
