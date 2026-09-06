// lib/screens/login_qr_scan_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/firebase_service.dart';
import '../services/qr_login_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../helpers/localization_helper.dart';
import '../widgets/barcode_scanner_view.dart';
import 'main_screen.dart';
import 'subscription_expired_screen.dart';

/// شاشة تسجيل الدخول عبر رمز QR: تمسح الرمز، تفك تشفيره بمفتاح التطبيق،
/// ثم تُسجّل الدخول بنفس طريقة تسجيل الدخول العادية (رقم + كلمة مرور).
class LoginQrScanScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;

  const LoginQrScanScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChange,
  });

  @override
  State<LoginQrScanScreen> createState() => _LoginQrScanScreenState();
}

class _LoginQrScanScreenState extends State<LoginQrScanScreen> {
  bool _isScanPaused = false;
  bool _isLoggingIn = false;
  bool _isUploading = false;
  String _errorMessage = '';

  Future<void> _handleDetected(String raw) async {
    if (_isScanPaused) return;

    setState(() {
      _isScanPaused = true;
      _errorMessage = '';
    });

    await _processCredentials(raw);
  }

  // ⭐ رفع صورة QR من المعرض وقراءتها بـ ML Kit ثم معالجتها كمسح عادي
  Future<void> _handleUpload() async {
    if (_isScanPaused) return;

    setState(() {
      _isScanPaused = true;
      _isUploading = true;
      _errorMessage = '';
    });

    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (picked == null) {
        // ⭐ المستخدم ألغى الاختيار
        _resetScanner();
        return;
      }

      final inputImage = InputImage.fromFilePath(picked.path);
      final scanner = BarcodeScanner(formats: const [BarcodeFormat.qrCode]);
      final barcodes = await scanner.processImage(inputImage);
      await scanner.close();

      if (!mounted) return;

      if (barcodes.isEmpty) {
        _showInvalidQrError();
        return;
      }

      final raw = barcodes.first.rawValue;
      if (raw == null || raw.isEmpty) {
        _showInvalidQrError();
        return;
      }

      await _processCredentials(raw);
    } catch (e) {
      // ⭐ لا نسجّل محتوى الرمز أبداً — رمز الخطأ فقط
      AppConfig.logError('QR image scan error', e);
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _isScanPaused = false;
        _errorMessage = LocalizationHelper.qrLoginUploadError;
      });
    }
  }

  void _resetScanner() {
    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _isScanPaused = false;
    });
  }

  // ⭐ منطق تسجيل الدخول المشترك بين مسح الكاميرا ورفع الصورة
  Future<void> _processCredentials(String raw) async {
    QrLoginCredentials? credentials = QrLoginService.decryptCredentials(raw);

    if (credentials == null) {
      _showInvalidQrError();
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() => _isLoggingIn = true);

    final authService = AuthService.instance;
    bool success;
    try {
      success = await authService.login(
        phone: credentials.phone,
        password: credentials.password,
      );
    } catch (e) {
      // ⭐ لا نُسجّل محتوى الرمز (هاتف/كلمة مرور) — رمز الخطأ فقط
      AppConfig.logError('QR login attempt failed', e);
      if (!mounted) return;
      final message = e.toString().startsWith('Exception: ')
          ? e.toString().substring(11)
          : e.toString();
      setState(() {
        _isLoggingIn = false;
        _isUploading = false;
        _isScanPaused = false;
        _errorMessage = message == 'null'
            ? LocalizationHelper.loginError
            : message;
      });
      return;
    } finally {
      // ⭐ اعتبار الرمز مستهلكاً: نتخلص من الإشارة إلى كلمة المرور
      // المفكوكة فور استخدامها حتى لا تبقى في الذاكرة.
      // TODO(C-1): الاستهلاك الحقيقي (single-use) يحتاج الخادم — رمز
      // لمرة واحدة يصدره Cloud Function ويلغيه بعد أول استخدام؛ بدون
      // خادم لا يمكن منع إعادة استخدام صورة الرمز خلال مدة صلاحيته.
      credentials = null;
    }

    if (!mounted) return;

    setState(() => _isLoggingIn = false);

    if (success) {
      HapticFeedback.lightImpact();

      // ⭐ مزامنة صريحة بنفس نمط SplashScreen قبل فحص الاشتراك:
      // نرفع البيانات غير المتزامنة إلى Firebase ثم نجلب البيانات الناقصة
      // ونُحدّث Hive قبل الانتقال للشاشة الرئيسية.
      final db = DatabaseService.instance;
      final syncService = SyncService();
      final firebaseService = FirebaseService();

      try {
        if (syncService.isOnline) {
          AppConfig.log('QR login: running initial sync...');
          await syncService.syncNow().timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  AppConfig.log('QR login sync timed out, continuing to app');
                },
              );
        } else {
          AppConfig.log('QR login: no internet, using local data only');
        }
      } catch (e) {
        AppConfig.logError('QR login: data loading error', e);
      }

      // ⭐ تحديث بيانات الاشتراك من Firestore إلى Hive مع إعادة محاولة
      // (أول استعلامات Firestore بعد تسجيل الدخول مباشرة قد تفشل مؤقتاً،
      //  لذلك نعيد المحاولة قبل إظهار "الاشتراك منتهي")
      Map<String, dynamic>? subInfo;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final userId = firebaseService.currentUser?.uid;
          if (userId == null) break;
          subInfo = await firebaseService.loadAndSaveSubscriptionInfo(userId);
          if (subInfo != null) {
            AppConfig.log(
                'QR login: subscription refreshed on attempt ${attempt + 1}');
            break;
          }
        } catch (e) {
          AppConfig.logError(
              'QR login: subscription refresh attempt ${attempt + 1} failed',
              e);
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }

      if (!mounted) return;

      // ⭐ فحص الاشتراك: يبدأ من Hive/نتيجة التحديث كخط أساس
      // ثم يتحقق من Firestore بمهلة كافية لتفادي الفشل المؤقت.
      bool isActive = false;
      final endDate = db.getSubscriptionEndDate();
      final isActiveFromHive = db.getSubscriptionActive();
      if (endDate != null) {
        final now = DateTime.now();
        if (now.isBefore(endDate)) {
          isActive = true;
        }
      } else {
        isActive = isActiveFromHive;
      }
      if (subInfo != null) {
        isActive = true;
      }

      try {
        final firebaseActive =
            await firebaseService.isSubscriptionActive().timeout(
                  const Duration(seconds: 10),
                  onTimeout: () => isActive,
                );
        isActive = firebaseActive;
      } catch (e) {
        AppConfig.logError(
            'QR login: subscription check failed, using Hive data', e);
      }

      AppConfig.log('QR login subscription decision: $isActive');

      if (!mounted) return;

      if (isActive) {
        _navigateToMain();
      } else {
        _navigateToSubscriptionExpired();
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _isUploading = false;
        _isScanPaused = false;
        _errorMessage = LocalizationHelper.loginError;
      });
    }
  }

  void _showInvalidQrError() {
    if (!mounted) return;
    setState(() {
      _isLoggingIn = false;
      _isUploading = false;
      _isScanPaused = false;
      _errorMessage = LocalizationHelper.qrLoginInvalidCode;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _errorMessage == LocalizationHelper.qrLoginInvalidCode) {
        setState(() => _errorMessage = '');
      }
    });
  }

  void _navigateToMain() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => MainScreen(
          themeMode: widget.themeMode,
          onThemeToggle: () {},
          onThemeModeChange: widget.onThemeModeChange,
        ),
      ),
      (route) => false,
    );
  }

  void _navigateToSubscriptionExpired() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => SubscriptionExpiredScreen(
          themeMode: widget.themeMode,
          onThemeModeChange: widget.onThemeModeChange,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(
          LocalizationHelper.qrLoginTitle,
          style: AppTextStyles.headline4(color: titleColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_rounded, color: accentColor),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: accentColor,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    LocalizationHelper.qrLoginSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium(color: bodyColor),
                  ),
                  const SizedBox(height: 20),
                  BarcodeScannerView(
                    formats: const [BarcodeFormat.qrCode],
                    onBarcodeDetected: _handleDetected,
                    paused: _isScanPaused || _isLoggingIn,
                    onClose: () => Navigator.pop(context),
                    onScannerError: (message) {
                      if (mounted) {
                        setState(() => _errorMessage = message);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed:
                          (_isScanPaused || _isLoggingIn) ? null : _handleUpload,
                      icon: Icon(
                        Icons.photo_library_outlined,
                        size: 20,
                        color: accentColor,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          LocalizationHelper.qrLoginUpload,
                          style: AppTextStyles.buttonText(
                            color: accentColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: accentColor.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_isLoggingIn || _isUploading)
                    Column(
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(accentColor),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isLoggingIn
                              ? LocalizationHelper.qrLoginSigningIn
                              : LocalizationHelper.qrLoginUploading,
                          style: AppTextStyles.bodyMedium(color: bodyColor),
                        ),
                      ],
                    )
                  else if (_errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style:
                                  AppTextStyles.bodyMedium(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}