import 'dart:typed_data';
import 'platform_file_helper_stub.dart'
    if (dart.library.io) 'platform_file_helper_mobile.dart'
    if (dart.library.html) 'platform_file_helper_web.dart';

Future<Uint8List> getBytesFromPathOrUrl(String pathOrUrl) {
  return getBytesFromPathOrUrlImpl(pathOrUrl);
}
