// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:window_manager/window_manager.dart';
import 'firebase_options.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'services/database_service.dart';
import 'services/cart_service.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'services/remote_config_service.dart';
import 'services/sync_service.dart';
import 'helpers/localization_helper.dart';
import 'helpers/direction_helper.dart';
import 'helpers/platform_helper.dart';
import 'services/barcode_input_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⭐ Windows: نافذة سطح مكتب + قارئ USB
  if (PlatformHelper.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      title: 'Hanoti',
      size: Size(1200, 800),
      minimumSize: Size(900, 640),
      center: true,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    BarcodeInputService.instance.init();
  }

  // ⭐ 1. التهيئة المحلية الفورية (Hive)
  await EasyLocalization.ensureInitialized();
  await DatabaseService.instance.init();
  await AuthService.instance.init();

  // ⭐ 2. تهيئة Firebase مع معالجة أفضل للويب
  try {
    AppConfig.log('===== Initializing Firebase =====');

    // ⭐ التحقق من وجود خيارات للويب
    FirebaseOptions? options;
    try {
      options = DefaultFirebaseOptions.currentPlatform;
      AppConfig.log('✅ Firebase options loaded successfully');
    } catch (e) {
      AppConfig.logError('⚠️ Could not load Firebase options', e);
      AppConfig.log('⚠️ Continuing without Firebase...');
    }

    if (options != null) {
      try {
        await Firebase.initializeApp(options: options).timeout(
          const Duration(seconds: 10),
        );

        // ⭐ App Check: يمنع الاتصال بقاعدة البيانات من خارج التطبيق.
        // التفعيل الكامل يتم من Firebase Console (Play Integrity على أندرويد).
        // في حال الفشل نكمل دون تعطيل التطبيق.
        try {
          await FirebaseAppCheck.instance.activate();
          AppConfig.log('✅ Firebase App Check activated');
        } catch (e) {
          AppConfig.logError('⚠️ Firebase App Check activation failed', e);
        }

        AppConfig.log('✅ Firebase initialized successfully');
      } on TimeoutException {
        AppConfig.log('⚠️ Firebase initializeApp timed out, continuing offline');
      }
    } else {
      AppConfig.log('⚠️ No Firebase options available, skipping initialization');
    }
  } catch (e) {
    AppConfig.logError('⚠️ Firebase init error', e);
    // ⭐ لا نعيد إلقاء الخطأ، بل نستمر بدون Firebase (الوضع دون اتصال)
  }

  // ⭐ 3. تهيئة FirebaseService فقط إذا كان Firebase مهيأ
  try {
    AppConfig.log('===== Initializing FirebaseService =====');

    // ⭐ التحقق من تهيئة Firebase
    if (Firebase.apps.isNotEmpty) {
      await FirebaseService().init();
      AppConfig.log('✅ FirebaseService initialized successfully');

      // ⭐ Remote Config: مدة التجربة تُدار عن بُعد (best-effort)
      try {
        await RemoteConfigService.instance.init();
        AppConfig.log('✅ RemoteConfigService initialized');
      } catch (e) {
        AppConfig.logError('⚠️ RemoteConfigService init error', e);
      }
    } else {
      AppConfig.log('⚠️ Firebase not initialized, skipping FirebaseService');
    }
  } catch (e) {
    AppConfig.logError('⚠️ FirebaseService init error', e);
  }

  // ⭐ 4. تهيئة SyncService (يعمل حتى بدون Firebase)
  try {
    AppConfig.log('===== Initializing SyncService =====');
    await SyncService().init().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        AppConfig.log('⏰ SyncService init timed out, continuing in background');
      },
    );
    AppConfig.log('✅ SyncService initialized successfully');
  } catch (e) {
    AppConfig.logError('⚠️ SyncService init error', e);
  }

  // ⭐ 5. إطلاق التطبيق
  final savedTheme = await _loadSavedThemeMode();
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('ar', 'SA'),
        Locale('fr', 'FR'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('ar', 'SA'),
      useOnlyLangCode: true,
      saveLocale: true,
      child: POSApp(initialThemeMode: savedTheme),
    ),
  );
}

// ⭐ تحميل وضع المظهر المحفوظ (الافتراضي: اتباع النظام)
Future<ThemeMode> _loadSavedThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    switch (saved) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  } catch (e) {
    return ThemeMode.system;
  }
}

// ⭐ حفظ وضع المظهر المختار يدوياً
Future<void> _saveThemeMode(ThemeMode mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('theme_mode', value);
  } catch (e) {
    // تجاهل فشل الحفظ
  }
}

class POSApp extends StatefulWidget {
  final ThemeMode initialThemeMode;

  const POSApp({super.key, this.initialThemeMode = ThemeMode.system});

  @override
  State<POSApp> createState() => _POSAppState();
}

class _POSAppState extends State<POSApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }

  void setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    _saveThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CartService(),
      child: MaterialApp(
        title: LocalizationHelper.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        builder: (context, child) {
          return Directionality(
            textDirection: appTextDirection(context.locale),
            child: child!,
          );
        },
        home: SplashScreen(
          themeMode: _themeMode,
          onThemeModeChange: setThemeMode,
        ),
      ),
    );
  }
}
