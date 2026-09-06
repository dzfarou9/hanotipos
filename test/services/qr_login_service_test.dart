import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/services/qr_login_service.dart';

void main() {
  // ملح ثابت بصيغة 32 حرفاً ست عشرية (نفس شكل generateSalt)
  const salt = '0123456789abcdef0123456789abcdef';

  group('QrLoginService', () {
    test('encryptCredentials produces a v4 string with the app prefix', () {
      final raw = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
      );

      expect(raw.startsWith('HANOTI_QR:4:$salt:'), isTrue);
    });

    test('decryptCredentials returns the original phone and password', () {
      final raw = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
      );

      final credentials = QrLoginService.decryptCredentials(raw);

      expect(credentials, isNotNull);
      expect(credentials!.phone, '0551234567');
      expect(credentials.password, 'secret123');
    });

    test('decryptCredentials returns null for a string without the prefix',
        () {
      final credentials =
          QrLoginService.decryptCredentials('592018001234567890');

      expect(credentials, isNull);
    });

    test('decryptCredentials returns null for garbage after the prefix', () {
      final credentials = QrLoginService
          .decryptCredentials('HANOTI_QR:4:$salt:not-valid-base64!!');

      expect(credentials, isNull);
    });

    test('decryptCredentials rejects legacy v3 payloads (universal key)', () {
      // الصيغة القديمة v3 لم تعد مدعومة — يجب رفضها حتى لو كانت صحيحة البنية
      final credentials =
          QrLoginService.decryptCredentials('HANOTI_QR:3:whateverpayload');

      expect(credentials, isNull);
    });

    test('decryptCredentials rejects an invalid salt format', () {
      final raw = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
      );
      // استبدال الملح بصيغة غير ست عشرية يجب أن يفكك التحقق
      final badSalt = 'ZZZZ456789abcdef0123456789abcdef';
      final tampered = raw.replaceFirst(salt, badSalt);

      expect(QrLoginService.decryptCredentials(tampered), isNull);
    });

    test('decryptCredentials returns null for tampered encrypted payload', () {
      final raw = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
      );
      final payload = raw.substring('HANOTI_QR:4:$salt:'.length);

      final tampered =
          'HANOTI_QR:4:$salt:${payload.substring(0, payload.length - 1)}x';

      expect(QrLoginService.decryptCredentials(tampered), isNull);
    });

    test('encryptCredentials uses a fresh random IV each time', () {
      final a = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
      );
      final b = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
      );

      // نفس البيانات يجب أن تُنتج حمولة مختلفة (IV عشوائي لكل تشفير)
      expect(a, isNot(b));
      // وكلاهما قابل لفك التشفير
      expect(QrLoginService.decryptCredentials(a)?.password, 'secret123');
      expect(QrLoginService.decryptCredentials(b)?.password, 'secret123');
    });

    test('different salts produce non-interoperable payloads', () {
      // مفتاح كل حساب مشتق من الملح — حمولة ملح لا تُفك بمفتاح ملح آخر
      final raw = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
      );
      const otherSalt = 'ffffffffffffffffffffffffffffffff';
      final crossAccount = raw.replaceFirst(salt, otherSalt);

      expect(QrLoginService.decryptCredentials(crossAccount), isNull);
    });

    test('encryptCredentials throws on invalid salt format', () {
      expect(
        () => QrLoginService.encryptCredentials(
          phone: '0551234567',
          password: 'secret123',
          salt: 'too-short',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('decryptCredentials returns null for an empty string', () {
      expect(QrLoginService.decryptCredentials(''), isNull);
    });

    test('decryptCredentials returns null for an expired code', () {
      // تتجاوز المدة سماحية فرق الساعة (10 ثوانٍ) فيُرفض الرمز منتهياً
      final raw = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
        validity: const Duration(seconds: -30),
      );

      expect(QrLoginService.decryptCredentials(raw), isNull);
    });

    test('decryptCredentials rejects a forged far-future expiry', () {
      // لا يجوز لملفّق أن يطيل عمر الحمولة beyond maxFutureSkew (120s)
      final raw = QrLoginService.encryptCredentials(
        phone: '0551234567',
        password: 'secret123',
        salt: salt,
        validity: const Duration(days: 1),
      );

      expect(QrLoginService.decryptCredentials(raw), isNull);
    });
  });
}
