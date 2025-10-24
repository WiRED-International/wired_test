import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

final _secureStorage = const FlutterSecureStorage();

/// Opens a Hive box encrypted with AES-256.
/// The key is stored securely in FlutterSecureStorage so it persists across app launches.
Future<Box<T>> openEncryptedBox<T>(String name) async {
  // Retrieve or create the AES key
  String? encodedKey = await _secureStorage.read(key: 'hive_key_$name');
  if (encodedKey == null) {
    final newKey = Hive.generateSecureKey();
    await _secureStorage.write(
      key: 'hive_key_$name',
      value: base64UrlEncode(newKey),
    );
    encodedKey = base64UrlEncode(newKey);
  }

  // Decode key and open encrypted box
  final key = base64Url.decode(encodedKey);
  return await Hive.openBox<T>(
    name,
    encryptionCipher: HiveAesCipher(key),
  );
}