import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

class SecureFileCacheService {
  static final SecureFileCacheService _instance =
      SecureFileCacheService._internal();
  factory SecureFileCacheService() => _instance;
  SecureFileCacheService._internal();

  static const String _secret = 'stagiaire-secure-media-cache-v1';
  static const int _ivLength = 16;
  final Random _random = Random.secure();

  Uint8List get _key =>
      Uint8List.fromList(sha256.convert(utf8.encode(_secret)).bytes);

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)));
  }

  PaddedBlockCipherImpl _cipher(bool forEncryption, Uint8List iv) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      forEncryption,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(_key), iv),
        null,
      ),
    );
    return cipher;
  }

  Uint8List encryptBytes(Uint8List plainBytes) {
    final iv = _randomBytes(_ivLength);
    final encrypted = _cipher(true, iv).process(plainBytes);
    return Uint8List.fromList([...iv, ...encrypted]);
  }

  Uint8List decryptBytes(Uint8List encryptedBytes) {
    if (encryptedBytes.length <= _ivLength) return Uint8List(0);
    final iv = encryptedBytes.sublist(0, _ivLength);
    final payload = encryptedBytes.sublist(_ivLength);
    return _cipher(false, iv).process(payload);
  }

  Future<File> writeEncrypted(File encryptedFile, Uint8List plainBytes) async {
    if (!await encryptedFile.parent.exists()) {
      await encryptedFile.parent.create(recursive: true);
    }
    return encryptedFile.writeAsBytes(encryptBytes(plainBytes), flush: true);
  }

  Future<File?> decryptToRuntimeFile(
    File encryptedFile,
    String runtimeFileName,
  ) async {
    if (!await encryptedFile.exists() || await encryptedFile.length() == 0) {
      return null;
    }
    final runtimeDir = await _runtimeDirectory();
    final runtimeFile =
        File('${runtimeDir.path}${Platform.pathSeparator}$runtimeFileName');
    if (await runtimeFile.exists() && await runtimeFile.length() > 0) {
      return runtimeFile;
    }
    final plainBytes = decryptBytes(await encryptedFile.readAsBytes());
    if (plainBytes.isEmpty) return null;
    return runtimeFile.writeAsBytes(plainBytes, flush: true);
  }

  Future<Directory> _runtimeDirectory() async {
    final baseDir = await getTemporaryDirectory();
    final dir = Directory(
      '${baseDir.path}${Platform.pathSeparator}stagiaire_secure_cache_runtime',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
