// lib/widgets/barcode_scanner_view.dart

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../config/app_config.dart';
import '../helpers/localization_helper.dart';
import '../services/scanner_feedback_service.dart';
import '../theme/app_colors.dart';

/// واجهة ماسح الباركود (الكاميرا + المعالجة + الطبقة البصرية).
///
/// يعتمد على [CameraController.startImageStream] (بث مباشر للإطارات) بدلاً من
/// التقاط صور منفصلة، مع قفل معالجة متسلسل يمنع تداخل الفحوصات،
/// ويمنع تكرار تسجيل نفس القيمة طالما بقي الباركود ظاهراً في الكاميرا.
class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({
    super.key,
    required this.onBarcodeDetected,
    this.onClose,
    this.paused = false,
    this.onScannerError,
    this.formats = _defaultFormats,
  });

  static const List<BarcodeFormat> _defaultFormats = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upca,
    BarcodeFormat.upce,
  ];

  /// يُستدعى عند التعرف على باركود صالح.
  final void Function(String barcode) onBarcodeDetected;

  /// يُستدعى عند الضغط على زر الإغلاق داخل الواجهة.
  final VoidCallback? onClose;

  /// عند true تتعطل حلقة المعالجة مؤقتاً (لا تُلتقط صور ولا تُقرأ باركودات).
  /// يُستخدم لإيقاف الماسح أثناء فتح نافذة حوارية فوقه.
  final bool paused;

  /// يُستدعى عند فشل تهيئة الكاميرا أو الماسح (رسالة قابلة للعرض).
  final ValueChanged<String>? onScannerError;

  /// صيغ الرموز المقبولة. الافتراضي رموز المنتجات (EAN/UPC)،
  /// ويمكن تمرير [BarcodeFormat.qrCode] لمسح رموز QR.
  final List<BarcodeFormat> formats;

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ⭐ ضبط إيقاع المعالجة: فاصل زمني بين معالجة الإطارات + فترة تهدئة بعد المسح
  static const Duration _minFrameInterval = AppConfig.minFrameInterval;
  static const Duration _cooldownDuration = AppConfig.scanCooldown;
  static const int _emptyFramesToReArm = AppConfig.emptyFramesToReArm;

  CameraController? _cameraController;
  BarcodeScanner? _barcodeScanner;

  bool _isCameraReady = false;
  bool _isFlashOn = false;
  bool _wasDetected = false;
  bool _disposed = false;
  String? _initError;

  // ⭐ منع تكرار تسجيل نفس الباركود: لا يُعاد الإرسال إلا بعد اختفاء القيمة
  String? _lastFiredBarcode;
  int _emptyFrameStreak = 0;

  // ⭐ عداد الجلسات: يُلغي معالجة الإطارات القديمة عند إعادة تهيئة الكاميرا
  int _session = 0;

  // ⭐ قفل المعالجة: إطار واحد فقط قيد المعالجة في أي لحظة
  bool _isProcessing = false;

  // ⭐ إيقاع المعالجة: يتجاهل الإطارات الواردة خلال الفاصل الزمني
  final Stopwatch _processTimer = Stopwatch();

  // ⭐ فترة تهدئة بعد كل مسح ناجح: لا يُقبل أي فحص جديد خلالها
  bool _inCooldown = false;
  Timer? _cooldownTimer;

  late final AnimationController _scanLineController;
  Timer? _successFlashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _initBarcodeScanner();
    if (!widget.paused) {
      _startCamera();
    }
  }

  @override
  void didUpdateWidget(BarcodeScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused != oldWidget.paused) {
      if (widget.paused) {
        _scanLineController.stop();
        // ⭐ فقط إيقاف بث الصور، لا نعيد تشغيل الكاميرا كاملة
        _cameraController?.stopImageStream();
        _isProcessing = false;
        _inCooldown = false;
      } else {
        _scanLineController.repeat(reverse: true);
        // ⭐ إذا رُكّب الجهاز paused ثم فُكّ، الكاميرا لم تُبدأ أصلاً —
        // يجب تشغيلها كاملة، لا مجرد إعادة فتح البث.
        if (_cameraController == null || !_cameraController!.value.isInitialized) {
          _startCamera();
        } else {
          _startImageStream();
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartCamera();
    } else if (state == AppLifecycleState.paused) {
      _stopCamera();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _successFlashTimer?.cancel();
    _cooldownTimer?.cancel();
    _scanLineController.dispose();
    _stopCamera();
    _barcodeScanner?.close();
    _barcodeScanner = null;
    super.dispose();
  }

  Future<void> _initBarcodeScanner() async {
    try {
      _barcodeScanner = BarcodeScanner(formats: widget.formats);
    } catch (e) {
      AppConfig.logError('⚠️ Failed to initialize barcode scanner', e);
      _reportError(LocalizationHelper.cameraError);
    }
  }

  // ==================== الكاميرا ====================

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _reportError(LocalizationHelper.cameraUnavailable);
        return;
      }
      if (!mounted || _disposed) return;

      final camera = cameras.first;

      // ⭐ إلغاء أي حلقة معالجة سابقة وتحرير الكاميرا القديمة إن وُجدت
      _session++;
      final oldController = _cameraController;
      _cameraController = null;
      if (oldController != null) {
        try {
          await oldController.dispose();
        } catch (_) {
          // تجاهل أخطاء التحرير
        }
      }

      _cameraController = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        // ⭐ Android: يطلب NV21 فيحوّله CameraX ناتيفياً إلى إطار واحد جاهز لـ ML Kit
        // (يتجنب النسخ والتحويل في دارت). iOS: BGRA8888 هو الصيغة المدعومة.
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted || _disposed) return;
      setState(() {
        _isCameraReady = true;
        _initError = null;
      });
      _startImageStream();
    } on CameraException catch (e) {
      AppConfig.logError('⚠️ Camera permission/init error: ${e.code} - ${e.description}', e);
      _reportError(LocalizationHelper.cameraUnavailable);
    } catch (e) {
      AppConfig.logError('⚠️ Camera initialization error', e);
      _reportError('${LocalizationHelper.cameraError}: $e');
    }
  }

  Future<void> _restartCamera() async {
    await _stopCamera();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && !_disposed && !widget.paused) await _startCamera();
  }

  void _reportError(String message) {
    if (_disposed) return;
    if (mounted && _initError == null) {
      setState(() => _initError = message);
    }
    widget.onScannerError?.call(message);
  }

  Future<void> _stopCamera() async {
    _isCameraReady = false;
    _isProcessing = false;
    _inCooldown = false;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _processTimer.stop();
    final controller = _cameraController;
    _cameraController = null;

    if (controller == null) return;

    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        // تجاهل أخطاء إيقاف البث
      }
    }

    if (controller.value.isInitialized) {
      try {
        await controller.dispose();
      } catch (_) {
        // تجاهل أخطاء التحرير
      }
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final next = !_isFlashOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _isFlashOn = next);
    } catch (e) {
      AppConfig.logError('⚠️ Flash toggle error', e);
      _showMessage(LocalizationHelper.flashError);
    }
  }

  // ==================== المعالجة ====================

  // ⭐ بث مباشر: يبدأ استقبال إطارات الكاميرا فور تهيئتها
  Future<void> _startImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;

    try {
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      AppConfig.logError('⚠️ Image stream error: ${e.code} - ${e.description}', e);
      _reportError(LocalizationHelper.cameraError);
    } catch (e) {
      AppConfig.logError('⚠️ Image stream error', e);
      _reportError('${LocalizationHelper.cameraError}: $e');
    }
  }

  // ⭐ معالجة إطار مباشر: يتجاهل الإطارات أثناء الانشغال أو التهدئة أو الإيقاف
  Future<void> _onFrame(CameraImage image) async {
    final controller = _cameraController;
    if (controller == null || _disposed || !mounted) return;
    if (widget.paused || _inCooldown || _isProcessing) return;

    // ⭐ تقليل الضغط على الأجهزة الضعيفة: لا نعالج أكثر من إطار كل 150 مللي
    if (_processTimer.isRunning &&
        _processTimer.elapsedMilliseconds < _minFrameInterval.inMilliseconds) {
      return;
    }
    _processTimer
      ..reset()
      ..start();

    final scanner = _barcodeScanner;
    if (scanner == null) return;

    final session = _session;
    _isProcessing = true;
    try {
      final barcodes = await scanner.processImage(_frameToInputImage(image));
      if (_disposed || !mounted) return;
      // ⭐ إلغاء نتيجة الإطار إذا تغيّرت الكاميرا أو الجلسة أثناء المعالجة
      if (session != _session || !identical(_cameraController, controller)) {
        return;
      }

      if (barcodes.isNotEmpty) {
        final rawValue = barcodes.first.rawValue;
        if (rawValue != null && rawValue.isNotEmpty) {
          _emptyFrameStreak = 0;
          // ⭐ لا يعيد نفس القيمة ما دامت ظاهرة؛ ويبدأ فترة تهدئة بعد كل مسح
          if (rawValue != _lastFiredBarcode) {
            _lastFiredBarcode = rawValue;
            _onBarcodeDetected(rawValue);
            _startCooldown();
          }
        }
      } else if (_lastFiredBarcode != null) {
        // ⭐ إعادة التسلح بعد اختفاء الباركود من الإطار
        _emptyFrameStreak++;
        if (_emptyFrameStreak >= _emptyFramesToReArm) {
          _lastFiredBarcode = null;
          _emptyFrameStreak = 0;
        }
      }
    } catch (e) {
      // تجاهل أخطاء المعالجة العابرة
      AppConfig.logError('⚠️ Frame processing error', e);
    } finally {
      _isProcessing = false;
    }
  }

  // ⭐ تحويل إطار الكاميرا إلى InputImage صالح لـ ML Kit بدون ملفات مؤقتة
  InputImage _frameToInputImage(CameraImage image) {
    // ⭐ المسار الأساسي (Android NV21 / iOS BGRA8888): مستوى واحد جاهز
    if (image.format.group == ImageFormatGroup.nv21 ||
        image.format.group == ImageFormatGroup.bgra8888) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _getInputImageRotation(),
          format: image.format.group == ImageFormatGroup.nv21
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    // ⭐ مسار احتياطي نادر (Android): يظهر أحياناً YUV_420_888 بثلاث مستويات
    // فيُحوَّل يدوياً إلى NV21 لأن ML Kit يقبل NV21/YV12 فقط من البايتات
    if (Platform.isAndroid && image.planes.length >= 3) {
      return InputImage.fromBytes(
        bytes: _planesToNv21(image),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _getInputImageRotation(),
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _getInputImageRotation(),
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  // ⭐ تحويل يدوي من YUV_420_888 (ثلاث مستويات) إلى NV21 (مستويان مدمجان)
  Uint8List _planesToNv21(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = yPlane.bytesPerRow * image.height;
    final uvSize = uPlane.bytesPerRow * (image.height ~/ 2);
    final out = Uint8List(ySize + uvSize);

    var position = 0;
    for (var row = 0; row < image.height; row++) {
      final start = row * yPlane.bytesPerRow;
      out.setRange(position, position + image.width, yPlane.bytes, start);
      position += image.width;
    }

    final uvHeight = image.height ~/ 2;
    final uvWidth = image.width ~/ 2;
    for (var row = 0; row < uvHeight; row++) {
      for (var col = 0; col < uvWidth; col++) {
        final vIndex =
            row * vPlane.bytesPerRow + col * (vPlane.bytesPerPixel ?? 1);
        final uIndex =
            row * uPlane.bytesPerRow + col * (uPlane.bytesPerPixel ?? 1);
        out[position++] = vPlane.bytes[vIndex];
        out[position++] = uPlane.bytes[uIndex];
      }
    }
    return out;
  }

  // ⭐ زاوية الاستدارة المطلوبة لـ ML Kit (تُتجاهل على iOS)
  InputImageRotation _getInputImageRotation() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return InputImageRotation.rotation0deg;
    }
    if (Platform.isIOS) return InputImageRotation.rotation0deg;

    final sensor = controller.description.sensorOrientation;
    final device = controller.value.deviceOrientation;
    final degrees = switch (device) {
      DeviceOrientation.portraitUp => sensor,
      DeviceOrientation.landscapeLeft => (sensor + 90) % 360,
      DeviceOrientation.landscapeRight => (sensor - 90) % 360,
      DeviceOrientation.portraitDown => (sensor + 180) % 360,
    };
    return switch (degrees) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };
  }

  // ⭐ فترة تهدئة بعد كل مسح ناجح: لا يُقبل أي فحص جديد خلالها
  void _startCooldown() {
    _inCooldown = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(_cooldownDuration, () {
      _inCooldown = false;
      _cooldownTimer = null;
    });
  }

  void _onBarcodeDetected(String barcode) {
    // ⭐ صوت "بيب" + اهتزاز خفيف عند كل مسح ناجح (نقطة البيع والمخزون)
    ScannerFeedbackService.playScanSuccess();
    if (mounted) setState(() => _wasDetected = true);
    _successFlashTimer?.cancel();
    _successFlashTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _wasDetected = false);
    });

    widget.onBarcodeDetected(barcode);
  }

  // ==================== الواجهة ====================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final flashColor =
        _wasDetected ? AppColors.success : accentColor;

    return Container(
      height: 280,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: flashColor.withValues(alpha: _wasDetected ? 1 : 0.5),
          width: _wasDetected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: flashColor.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraController != null &&
                _cameraController!.value.isInitialized)
              CameraPreview(_cameraController!),
            if (!_isCameraReady)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (_initError != null)
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.white, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      _initError!,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _restartCamera,
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 18),
                      label: Text(
                        LocalizationHelper.syncRetry,
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
            if (_wasDetected)
              Container(
                color: AppColors.success.withValues(alpha: 0.3),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            _buildScanWindowOverlay(accentColor),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    LocalizationHelper.posScanBarcode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onClose != null) ...[
              Positioned(
                top: 12,
                left: 12,
                child: _buildRoundButton(
                  icon: Icons.close_rounded,
                  onPressed: () => widget.onClose!(),
                ),
              ),
            ],
            Positioned(
              top: 12,
              right: 12,
              child: _buildRoundButton(
                icon: _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                onPressed: _toggleFlash,
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    LocalizationHelper.cameraHint,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  // ⭐ نافذة التركيز: إعتام خارج الإطار + زوايا + خط مسح متحرك
  Widget _buildScanWindowOverlay(Color accentColor) {
    const windowWidth = 240.0;
    const windowHeight = 120.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final left = (constraints.maxWidth - windowWidth) / 2;
        final top = (constraints.maxHeight - windowHeight) / 2 - 6;

        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: top,
              child: _buildDimLayer(),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: constraints.maxHeight - top - windowHeight,
              child: _buildDimLayer(),
            ),
            Positioned(
              top: top,
              left: 0,
              width: left,
              height: windowHeight,
              child: _buildDimLayer(),
            ),
            Positioned(
              top: top,
              right: 0,
              width: left,
              height: windowHeight,
              child: _buildDimLayer(),
            ),
            Positioned(
              top: top,
              left: left,
              width: windowWidth,
              height: windowHeight,
              child: Stack(
                children: [
                  _buildCorner(accentColor, Alignment.topLeft),
                  _buildCorner(accentColor, Alignment.topRight),
                  _buildCorner(accentColor, Alignment.bottomLeft),
                  _buildCorner(accentColor, Alignment.bottomRight),
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (context, child) {
                      final t = _scanLineController.value;
                      return Positioned(
                        top: 8 + t * (windowHeight - 16),
                        left: 12,
                        right: 12,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                accentColor,
                                accentColor,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDimLayer() {
    return Container(color: Colors.black.withValues(alpha: 0.55));
  }

  Widget _buildCorner(Color color, Alignment alignment) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;

    return Align(
      alignment: alignment,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
            bottom:
                isTop ? BorderSide.none : BorderSide(color: color, width: 3),
            left: isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
            right:
                isLeft ? BorderSide.none : BorderSide(color: color, width: 3),
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}