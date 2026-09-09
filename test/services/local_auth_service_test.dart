import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/services/local_auth_service.dart';

class InMemoryStore implements CredentialsStore {
  final Map<String, String> data = {};

  @override
  Future<Map<String, String?>> readAll() async => Map<String, String?>.from(data);

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late InMemoryStore store;
  late LocalAuthService local;

  setUp(() {
    store = InMemoryStore();
    local = LocalAuthService(store: store);
  });

  test('no local account initially', () async {
    expect(await local.hasLocalAccount(), isFalse);
  });

  test('create then verify succeeds', () async {
    await local.createLocalAccount(phone: '0500111222', password: 'secret1');
    expect(await local.hasLocalAccount(), isTrue);
    expect(
      await local.verifyCredentials(phone: '0500111222', password: 'secret1'),
      isTrue,
    );
  });

  test('verify with wrong password fails', () async {
    await local.createLocalAccount(phone: '0500111222', password: 'secret1');
    expect(
      await local.verifyCredentials(phone: '0500111222', password: 'wrong'),
      isFalse,
    );
  });

  test('verify with wrong phone fails', () async {
    await local.createLocalAccount(phone: '0500111222', password: 'secret1');
    expect(
      await local.verifyCredentials(phone: '0599999999', password: 'secret1'),
      isFalse,
    );
  });

  test('createLocalAccount twice throws StateError', () async {
    await local.createLocalAccount(phone: '0500111222', password: 'secret1');
    expect(
      () => local.createLocalAccount(phone: '0555', password: 'x'),
      throwsStateError,
    );
  });

  test('userId is stable across reads', () async {
    await local.createLocalAccount(phone: '0500111222', password: 'secret1');
    final id1 = await local.localUserId();
    final id2 = await local.localUserId();
    expect(id1, isNotNull);
    expect(id1, id2);
  });

  test('password is never stored in plaintext', () async {
    await local.createLocalAccount(phone: '0500111222', password: 'secret1');
    expect(store.data.containsValue('secret1'), isFalse);
  });
}
