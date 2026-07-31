import 'task_attachment_service_test_platform_stub.dart'
    if (dart.library.io) 'task_attachment_service_test_platform_io.dart';

Future<bool> verifyExternalPathIsRejected() =>
    verifyExternalPathIsRejectedImpl();
