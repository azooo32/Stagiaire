import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> getBytesFromPathOrUrlImpl(String pathOrUrl) async {
  final file = File(pathOrUrl);
  return await file.readAsBytes();
}
