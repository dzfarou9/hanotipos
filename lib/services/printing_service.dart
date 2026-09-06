// lib/services/printing_service.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../helpers/localization_helper.dart';
import '../models/cart_item_model.dart';
import '../models/sale_model.dart';
import 'auth_service.dart';
import 'receipt_data.dart';
import 'receipt_renderer.dart';

/// Raised when a receipt cannot be printed/shared so callers can show a
/// friendly, actionable message instead of a raw exception.
class ReceiptPrintException implements Exception {
  final String message;

  const ReceiptPrintException(this.message);

  @override
  String toString() => message;
}

class PrintingService {
  static const String storeName = 'HANOTI POS';
  static const String currency = 'DZD';

  // ==================== إنشاء PDF ====================

  static Future<Uint8List> generateInvoicePdf({
    required List<CartItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) {
    final data = _buildReceiptData(
      lines: _cartLines(items),
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      taxRate: taxRate,
      total: total,
      paymentMethod: paymentMethod,
      saleId: saleId,
      date: date,
      customerName: customerName,
      customerPhone: customerPhone,
      paperSize: paperSize,
    );
    return ThermalReceiptRenderer.buildPdf(data: data);
  }

  // ==================== طباعة الفاتورة ====================

  static Future<void> printInvoice({
    required List<CartItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) async {
    try {
      final data = _buildReceiptData(
        lines: _cartLines(items),
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        taxRate: taxRate,
        total: total,
        paymentMethod: paymentMethod,
        saleId: saleId,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        paperSize: paperSize,
      );

      final effectiveFormat = paperSize.format;

      // The system print dialog (Android/iOS print services) reaches
      // Bluetooth, USB and network thermal printers. When the printer
      // reports a thermal roll width we adapt the layout to it;
      // otherwise we fall back to the requested paper size.
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat printerFormat) async {
          final matched = ThermalReceiptRenderer.matchSize(printerFormat);
          return ThermalReceiptRenderer.buildPdf(
            data: data,
            format: matched?.format ?? effectiveFormat,
          );
        },
        name: LocalizationHelper.commonReceipt,
        format: effectiveFormat,
      );
    } on ReceiptPrintException {
      rethrow;
    } catch (e) {
      debugPrint('Print error: $e');
      throw ReceiptPrintException(LocalizationHelper.commonPrintFailed);
    }
  }

  // ==================== مشاركة الفاتورة ====================

  static Future<void> shareInvoice({
    required List<CartItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) async {
    try {
      final pdfData = await generateInvoicePdf(
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        taxRate: taxRate,
        total: total,
        paymentMethod: paymentMethod,
        saleId: saleId,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        paperSize: paperSize,
      );

      // حفظ PDF مؤقتاً
      final directory = await getTemporaryDirectory();
      // إزالة بقايا فواتير سابقة (قد تحتوي بيانات العميل) قبل المشاركة
      await _cleanupStaleInvoiceFiles(directory);
      final filePath = '${directory.path}/invoice_${_shortId(saleId)}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(pdfData);

      try {
        // مشاركة الملف
        await Share.shareXFiles(
          [XFile(filePath)],
          text:
              '${LocalizationHelper.printingInvoiceNo(_shortId(saleId).toUpperCase())}\n${LocalizationHelper.printingTotalLabel('$total $currency')}\n\n${LocalizationHelper.printingThankYou}',
        );
      } finally {
        // لا نترك نسخة من الفاتورة في الذاكرة المؤقتة بعد انتهاء المشاركة
        await _deleteInvoiceFile(file);
      }
    } catch (e) {
      debugPrint('Share error: $e');
      rethrow;
    }
  }

  // ==================== حفظ الفاتورة ====================

  /// Saves the receipt to a user-chosen location via the native
  /// "Save as" dialog (Android SAF / desktop). Returns `true` when the
  /// file was saved, `false` when the user cancelled. On platforms
  /// without a native save dialog (iOS/web) it falls back to the share
  /// sheet and returns `true`.
  static Future<bool> saveInvoice({
    required List<CartItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) async {
    final pdfData = await generateInvoicePdf(
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      taxRate: taxRate,
      total: total,
      paymentMethod: paymentMethod,
      saleId: saleId,
      date: date,
      customerName: customerName,
      customerPhone: customerPhone,
      paperSize: paperSize,
    );

    if (kIsWeb || (!kIsWeb && Platform.isIOS)) {
      await shareInvoice(
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        taxRate: taxRate,
        total: total,
        paymentMethod: paymentMethod,
        saleId: saleId,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        paperSize: paperSize,
      );
      return true;
    }

    try {
      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          data: pdfData,
          fileName: 'invoice_${_shortId(saleId).toUpperCase()}.pdf',
          mimeTypesFilter: const ['application/pdf'],
        ),
      );
      return savedPath != null;
    } on MissingPluginException {
      // Save-as unavailable on this platform: fall back to sharing.
      await shareInvoice(
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        taxRate: taxRate,
        total: total,
        paymentMethod: paymentMethod,
        saleId: saleId,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        paperSize: paperSize,
      );
      return true;
    } catch (e) {
      debugPrint('Save error: $e');
      rethrow;
    }
  }

  // ==================== طباعة/مشاركة فاتورة من سجل المبيعات ====================

  static Future<Uint8List> generateSalePdf({
    required List<SaleItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) {
    final data = _buildReceiptData(
      lines: _saleLines(items),
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      taxRate: taxRate,
      total: total,
      paymentMethod: paymentMethod,
      saleId: saleId,
      date: date,
      customerName: customerName,
      customerPhone: customerPhone,
      paperSize: paperSize,
    );
    return ThermalReceiptRenderer.buildPdf(data: data);
  }

  static Future<void> printSaleInvoice({
    required List<SaleItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) async {
    try {
      final data = _buildReceiptData(
        lines: _saleLines(items),
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        taxRate: taxRate,
        total: total,
        paymentMethod: paymentMethod,
        saleId: saleId,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        paperSize: paperSize,
      );

      final effectiveFormat = paperSize.format;

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat printerFormat) async {
          final matched = ThermalReceiptRenderer.matchSize(printerFormat);
          return ThermalReceiptRenderer.buildPdf(
            data: data,
            format: matched?.format ?? effectiveFormat,
          );
        },
        name: LocalizationHelper.commonReceipt,
        format: effectiveFormat,
      );
    } on ReceiptPrintException {
      rethrow;
    } catch (e) {
      debugPrint('Print error: $e');
      throw ReceiptPrintException(LocalizationHelper.commonPrintFailed);
    }
  }

  static Future<void> shareSaleInvoice({
    required List<SaleItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) async {
    try {
      final pdfData = await generateSalePdf(
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        taxRate: taxRate,
        total: total,
        paymentMethod: paymentMethod,
        saleId: saleId,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        paperSize: paperSize,
      );

      final directory = await getTemporaryDirectory();
      // إزالة بقايا فواتير سابقة (قد تحتوي بيانات العميل) قبل المشاركة
      await _cleanupStaleInvoiceFiles(directory);
      final filePath = '${directory.path}/invoice_${_shortId(saleId)}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(pdfData);

      try {
        await Share.shareXFiles(
          [XFile(filePath)],
          text:
              '${LocalizationHelper.printingInvoiceNo(_shortId(saleId).toUpperCase())}\n${LocalizationHelper.printingTotalLabel('$total $currency')}\n\n${LocalizationHelper.printingThankYou}',
        );
      } finally {
        // لا نترك نسخة من الفاتورة في الذاكرة المؤقتة بعد انتهاء المشاركة
        await _deleteInvoiceFile(file);
      }
    } catch (e) {
      debugPrint('Share error: $e');
      rethrow;
    }
  }

  // ==================== بناء بيانات الفاتورة ====================

static ReceiptData _buildReceiptData({
    required List<ReceiptLine> lines,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String saleId,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    double? taxRate,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) {
    final storePhone = AuthService.instance.storePhone;
    final info = (storePhone != null && storePhone.isNotEmpty)
        ? storePhone
        : LocalizationHelper.printingTitle;

    return ReceiptData(
      paperSize: paperSize,
      storeName: AuthService.instance.storeName ?? storeName,
      storeInfo: info,
      storeAddress: AuthService.instance.storeAddress,
      storeTaxId: AuthService.instance.storeTaxId,
      receiptId:
          LocalizationHelper.printingInvoiceNo(_shortId(saleId).toUpperCase()),
      date: LocalizationHelper.printingDate(_formatDate(date)),
      time: LocalizationHelper.printingTime(_formatTime(date)),
      customerName: customerName,
      customerPhone: customerPhone,
      paymentMethod: LocalizationHelper.paymentMethod(paymentMethod),
      items: lines,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      taxRate: taxRate,
      total: total,
      currency: currency,
      labels: ReceiptLabels(
        product: LocalizationHelper.printingProduct,
        qty: LocalizationHelper.printingQty,
        price: LocalizationHelper.printingPrice,
        total: LocalizationHelper.printingTotal,
        customer: LocalizationHelper.printingCustomerLabel,
        phone: LocalizationHelper.printingPhoneLabel,
        subtotal: LocalizationHelper.printingSubtotalLabel,
        discount: LocalizationHelper.printingDiscountLabel,
        tax: LocalizationHelper.printingTaxLabel,
        totalText: LocalizationHelper.printingTotalText,
        payment: LocalizationHelper.printingPayment(
          LocalizationHelper.paymentMethod(paymentMethod),
        ),
        thanks: LocalizationHelper.printingThankYou,
        visitAgain: LocalizationHelper.printingVisitAgain,
        taxIdLabel: LocalizationHelper.printingTaxIdLabel,
      ),
    );
  }

  // ==================== مساعدة ====================

  static List<ReceiptLine> _cartLines(List<CartItem> items) => items
      .map((item) => ReceiptLine(
            name: item.product.name,
            quantity: item.quantity,
            unitPrice: item.product.price,
            lineTotal: item.subtotal,
          ))
      .toList();

  static List<ReceiptLine> _saleLines(List<SaleItem> items) => items
      .map((item) => ReceiptLine(
            name: item.productName,
            quantity: item.quantity,
            unitPrice: item.price,
            lineTotal: item.subtotal,
          ))
      .toList();

  static String _shortId(String id) =>
      id.length >= 8 ? id.substring(0, 8) : id;

  /// يحذف ملف الفاتورة المؤقت بأمان — فشل الحذف (ملف مقفَل مثلاً)
  /// يجب ألا يعطّل عملية المشاركة.
  static Future<void> _deleteInvoiceFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Temp invoice cleanup failed: $e');
    }
  }

  /// تنظيف محدود لبقايا ملفات الفواتير السابقة في المجلد المؤقت
  /// (قد تحتوي بيانات عملاء من مشارعات لم تكتمل حذفها).
  static Future<void> _cleanupStaleInvoiceFiles(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith('invoice_') &&
            entity.path.toLowerCase().endsWith('.pdf')) {
          await _deleteInvoiceFile(entity);
        }
      }
    } catch (e) {
      debugPrint('Stale invoice cleanup failed: $e');
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}