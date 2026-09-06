// lib/services/receipt_renderer.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_data.dart';

/// Renders a [ReceiptData] into a thermal-optimized PDF receipt.
///
/// The layout is fully width-aware: it adapts to 58mm and 80mm rolls,
/// wraps long product names without breaking column alignment, and
/// produces output shaped like a commercial POS receipt.
class ThermalReceiptRenderer {
  ThermalReceiptRenderer._();

  static pw.Font? _regular;
  static pw.Font? _medium;
  static pw.Font? _bold;

  /// Loads (and caches) the bundled Tajawal fonts so Arabic and Latin
  /// both render correctly. Bundled locally, so it works offline.
  static Future<void> _ensureFonts() async {
    if (_regular != null) return;
    _regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'),
    );
    _medium = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tajawal-Medium.ttf'),
    );
    _bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'),
    );
  }

  /// Builds the receipt PDF bytes for [data].
  ///
  /// When [format] is given (e.g. the printer's reported format) the
  /// layout adapts to its width if it matches a known roll size,
  /// otherwise [data.paperSize] is used.
  static Future<Uint8List> buildPdf({
    required ReceiptData data,
    PdfPageFormat? format,
  }) async {
    await _ensureFonts();

    final pageFormat = format ?? data.paperSize.format;
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (_) => _buildReceipt(data, pageFormat),
      ),
    );

    return pdf.save();
  }

  /// Resolves a page format width to a known thermal paper size.
  /// Returns `null` when the format is not a thermal roll (e.g. A4).
  static ThermalPaperSize? matchSize(PdfPageFormat format) {
    final widthMm = format.width / PdfPageFormat.mm;
    if (widthMm <= 65) return ThermalPaperSize.mm58;
    if (widthMm <= 95) return ThermalPaperSize.mm80;
    return null;
  }

  static pw.Widget _buildReceipt(ReceiptData data, PdfPageFormat format) {
    final labels = data.labels;
    final paperSize = matchSize(format) ?? data.paperSize;
    final s = paperSize.scale;
    final isNarrow = paperSize == ThermalPaperSize.mm58;

    pw.TextStyle body(double size, {pw.Font? font, PdfColor? color}) =>
        pw.TextStyle(
          font: font ?? _regular,
          fontSize: size * s,
          color: color ?? PdfColors.black,
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ===== Store header =====
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              data.storeName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: _bold,
                fontSize: 16 * s,
                color: PdfColors.orange,
              ),
            ),
            if (data.storeInfo != null && data.storeInfo!.isNotEmpty) ...[
              pw.SizedBox(height: 2 * s),
              pw.Text(
                data.storeInfo!,
                textAlign: pw.TextAlign.center,
                style: body(9, color: PdfColors.grey700),
              ),
            ],
            if (data.storeAddress != null && data.storeAddress!.isNotEmpty) ...[
              pw.SizedBox(height: 1 * s),
              pw.Text(
                data.storeAddress!,
                textAlign: pw.TextAlign.center,
                style: body(8, color: PdfColors.grey700),
              ),
            ],
            if (data.storeTaxId != null && data.storeTaxId!.isNotEmpty) ...[
              pw.SizedBox(height: 1 * s),
              pw.Text(
                '${labels.taxIdLabel}: ${data.storeTaxId}',
                textAlign: pw.TextAlign.center,
                style: body(8, color: PdfColors.grey700),
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 6 * s),
        _dashedLine(),
        pw.SizedBox(height: 8 * s),

        // ===== Receipt info =====
        pw.Text(data.receiptId, style: body(9)),
        pw.SizedBox(height: 2 * s),
        pw.Text(data.date, style: body(9)),
        pw.SizedBox(height: 2 * s),
        pw.Text(data.time, style: body(9)),
        if (data.customerName != null && data.customerName!.isNotEmpty) ...[
          pw.SizedBox(height: 2 * s),
          pw.Text('${labels.customer}: ${data.customerName}', style: body(9)),
        ],
        if (data.customerPhone != null && data.customerPhone!.isNotEmpty) ...[
          pw.SizedBox(height: 2 * s),
          pw.Text('${labels.phone}: ${data.customerPhone}', style: body(9)),
        ],
        pw.SizedBox(height: 8 * s),
        _dashedLine(),
        pw.SizedBox(height: 8 * s),

        // ===== Items column header =====
        if (isNarrow)
          pw.Text(labels.product, style: body(8.5, font: _medium))
        else
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(labels.product, style: body(8.5, font: _medium)),
              ),
              pw.Text(
                '${labels.qty}   ${labels.price}   ${labels.total}',
                style: body(8.5, font: _medium),
              ),
            ],
          ),
        pw.SizedBox(height: 4 * s),

        // ===== Items =====
        ...data.items.map((item) => _itemRow(item, isNarrow, s)),
        pw.SizedBox(height: 8 * s),
        _dashedLine(),
        pw.SizedBox(height: 8 * s),

        // ===== Totals =====
        _totalRow(
          labels.subtotal,
          _money(data.subtotal, data.currency),
          body(9),
          PdfColors.black,
        ),
        if (data.discount > 0) ...[
          pw.SizedBox(height: 2 * s),
          _totalRow(
            labels.discount,
            '-${_money(data.discount, data.currency)}',
            body(9),
            PdfColors.red,
          ),
        ],
        if (data.tax > 0) ...[
          pw.SizedBox(height: 2 * s),
          _totalRow(
            _taxLabel(labels.tax, data.taxRate),
            _money(data.tax, data.currency),
            body(9),
            PdfColors.black,
          ),
        ],
        pw.SizedBox(height: 6 * s),
        _solidLine(thickness: 2),
        pw.SizedBox(height: 6 * s),
        _totalRow(
          labels.totalText,
          _money(data.total, data.currency),
          pw.TextStyle(
            font: _bold,
            fontSize: 13 * s,
            color: PdfColors.orange,
          ),
          PdfColors.orange,
        ),
        pw.SizedBox(height: 6 * s),
        pw.Text(labels.payment, style: body(9)),

        pw.SizedBox(height: 8 * s),

        // ===== Footer =====
        _dashedLine(),
        pw.SizedBox(height: 6 * s),
        pw.Text(
          labels.thanks,
          textAlign: pw.TextAlign.center,
          style: body(10, font: _bold),
        ),
        pw.SizedBox(height: 2 * s),
        pw.Text(
          labels.visitAgain,
          textAlign: pw.TextAlign.center,
          style: body(8, color: PdfColors.grey600),
        ),
      ],
    );
  }

  /// Renders a product line.
  ///
  /// 80mm: one row (name on the left, `qty x price  total` on the right).
  /// 58mm: two rows (name, then right-aligned amounts) for readability.
  static pw.Widget _itemRow(ReceiptLine item, bool isNarrow, double s) {
    if (isNarrow) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 4 * s),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(item.name, style: pw.TextStyle(fontSize: 8.5 * s)),
            pw.SizedBox(height: 1 * s),
            pw.Text(
              '${item.quantity} x ${_num(item.unitPrice)} = ${_num(item.lineTotal)}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 8 * s),
            ),
          ],
        ),
      );
    }

    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 3 * s),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(item.name, style: pw.TextStyle(fontSize: 9 * s)),
          ),
          pw.SizedBox(width: 6 * s),
          pw.Text(
            '${item.quantity} x ${_num(item.unitPrice)}   ${_num(item.lineTotal)}',
            style: pw.TextStyle(fontSize: 8.5 * s),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value,
    pw.TextStyle style,
    PdfColor color,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style.copyWith(color: color)),
        pw.Text(value, style: style.copyWith(color: color)),
      ],
    );
  }

  /// Dashed separator that fills the full page width.
  static pw.Widget _dashedLine({PdfColor color = PdfColors.black}) {
    return pw.Container(
      height: 1,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: List.generate(
          80,
          (_) => pw.Container(width: 3, height: 1, color: color),
        ),
      ),
    );
  }

  static pw.Widget _solidLine({
    double thickness = 1,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Container(
      height: thickness,
      width: double.infinity,
      color: color,
    );
  }

  static String _taxLabel(String tax, double? taxRate) {
    if (taxRate == null || taxRate <= 0) return tax;
    return '$tax ($taxRate%)';
  }

  static String _money(double value, String currency) =>
      '${value.toStringAsFixed(2)} $currency';

  static String _num(double value) => value.toStringAsFixed(2);
}