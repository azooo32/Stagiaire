import 'dart:io';
import 'package:flutter/foundation.dart';

/// Quick real check that the device can reach the internet (DNS lookup).
Future<bool> hasInternetConnection() async {
  if (kIsWeb) return true;
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
