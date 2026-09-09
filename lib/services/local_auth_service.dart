// lib/services/local_auth_service.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// تخزين بيانات الاعتماد المحلية — قابل للاستبدال في الاختبارات.
abstract class CredentialsStore {
  Future<Map<String, String?>> readAll();
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStoreCredentialsStore implements CredentialsStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<Map<String, String?>> readAll() => _storage.readAll();

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class LocalAuthService {
  static const String phoneKey = 'local_auth_phone_v1';
  static const String saltKey = 'local_auth_salt_v1';
  static const String hashKey = 'local_auth_hash_v1';
  static const String userIdKey = 'local_auth_userid_v1';

  static LocalAuthService? _instance;
  final CredentialsStore _store;

  LocalAuthService._(this._store);

  /// الاختبارات تمرر store لإرجاع نسخة جديدة؛ الاستخدام العادي يعيد singleton.
  factory LocalAuthService({CredentialsStore? store}) {
    if (store != null) return LocalAuthService._(store);
    return _instance ??= LocalAuthService._(SecureStoreCredentialsStore());
  }

  Future<Map<String, String?>> readAll() => _store.readAll();

  Future<bool> hasLocalAccount() async {
    final data = await _store.readAll();
    return (data[hashKey] ?? '').isNotEmpty;
  }

  Future<void> createLocalAccount({
    required String phone,
    required String password,
  }) async {
    final data = await _store.readAll();
    if ((data[hashKey] ?? '').isNotEmpty) {
      throw StateError('Local account already exists');
    }
    final salt = const Uuid().v4();
    final userId = const Uuid().v4();
    await _store.write(phoneKey, phone);
    await _store.write(saltKey, salt);
    await _store.write(hashKey, _hash(password, salt));
    await _store.write(userIdKey, userId);
  }

  Future<bool> verifyCredentials({
    required String phone,
    required String password,
  }) async {
    final data = await _store.readAll();
    final storedPhone = data[phoneKey];
    final storedHash = data[hashKey];
    final salt = data[saltKey];
    if (storedPhone == null || storedHash == null || salt == null) {
      return false;
    }
    if (storedPhone != phone) return false;
    return storedHash == _hash(password, salt);
  }

  Future<String?> localUserId() async {
    return (await _store.readAll())[userIdKey];
  }

  String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }
}
