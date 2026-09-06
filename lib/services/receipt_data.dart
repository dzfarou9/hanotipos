// lib/services/receipt_data.dart

import 'package:pdf/pdf.dart';

/// Thermal paper width support for common receipt printers.
///
/// `mm58` targets 58mm thermal printers (57mm printable roll).
/// `mm80` targets 80mm thermal printers (80mm printable roll).
enum ThermalPaperSize { mm58, mm80 }

extension ThermalPaperSizeX on ThermalPaperSize {
  /// The [PdfPageFormat] matching this paper size.
  PdfPageFormat get format => switch (this) {
        ThermalPaperSize.mm58 => PdfPageFormat.roll57,
        ThermalPaperSize.mm80 => PdfPageFormat.roll80,
      };

  /// Font size multiplier so the 58mm layout stays readable.
  double get scale => switch (this) {
        ThermalPaperSize.mm58 => 0.72,
        ThermalPaperSize.mm80 => 1.0,
      };
}

/// A single product line rendered on a thermal receipt.
class ReceiptLine {
  final String name;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
}

/// Localized strings used by the receipt renderer.
///
/// The renderer stays pure (no `.tr()` calls); the caller builds these
/// labels so rendering is deterministic and testable.
class ReceiptLabels {
  final String product;
  final String qty;
  final String price;
  final String total;

  final String customer;
  final String phone;

  final String subtotal;
  final String discount;
  final String tax;
  final String totalText;

  final String payment;

  final String thanks;
  final String visitAgain;
  final String taxIdLabel;

  const ReceiptLabels({
    required this.product,
    required this.qty,
    required this.price,
    required this.total,
    required this.customer,
    required this.phone,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.totalText,
    required this.payment,
    required this.thanks,
    required this.visitAgain,
    required this.taxIdLabel,
  });
}

/// Immutable payload describing a receipt to be rendered.
///
/// The rendering service only reads values from this object; it never
/// computes business totals, so sales/return/inventory/tax logic is
/// untouched.
class ReceiptData {
  final ThermalPaperSize paperSize;

  final String storeName;
  final String? storeInfo;
  final String? storeAddress;
  final String? storeTaxId;

  final String receiptId;
  final String date;
  final String time;

  final String? customerName;
  final String? customerPhone;

  final String paymentMethod;

  final List<ReceiptLine> items;

  final double subtotal;
  final double discount;
  final double tax;
  final double? taxRate;

  final double total;
  final String currency;

  final ReceiptLabels labels;

  const ReceiptData({
    this.paperSize = ThermalPaperSize.mm80,
    required this.storeName,
    this.storeInfo,
    this.storeAddress,
    this.storeTaxId,
    required this.receiptId,
    required this.date,
    required this.time,
    this.customerName,
    this.customerPhone,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    this.tax = 0,
    this.taxRate,
    required this.total,
    required this.currency,
    required this.labels,
  });
}