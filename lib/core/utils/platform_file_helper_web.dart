// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List> getBytesFromPathOrUrlImpl(String pathOrUrl) async {
  final request = await html.HttpRequest.request(
    pathOrUrl,
    method: 'GET',
    responseType: 'arraybuffer',
  );
  final ByteBuffer buffer = request.response as ByteBuffer;
  return buffer.asUint8List();
}
