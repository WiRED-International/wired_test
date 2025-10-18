import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';

class SecureHive {
  static const _keyName = 'hive_aes_key_v1';

  static Future<void> init({bool clearBoxesForDev = false}) async {
    await Hive.initFlutter();

    if (clearBoxesForDev) {
      // 🧹 Clear dev boxes to avoid schema mismatch (safe for dev only)
      await Hive.deleteBoxFromDisk('exam_attempts');
      await Hive.deleteBoxFromDisk('examBox');
    }
  }

  static Future<HiveAesCipher> getCipher() async {
    const storage = FlutterSecureStorage();
    String? base64Key = await storage.read(key: _keyName);

    if (base64Key == null) {
      final key = _generateSecureKey();
      base64Key = base64.encode(key);
      await storage.write(key: _keyName, value: base64Key);
    }
    final keyBytes = base64.decode(base64Key);
    return HiveAesCipher(keyBytes);
  }

  static List<int> _generateSecureKey() {
    final rand = Random.secure();
    return List<int>.generate(32, (_) => rand.nextInt(256));
  }
}