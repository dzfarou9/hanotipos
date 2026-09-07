// lib/helpers/localization_helper.dart

import 'package:easy_localization/easy_localization.dart';

class LocalizationHelper {
  // ==================== دوال عامة ====================

  static String get appName => 'app_name'.tr();
  static String get appTagline => 'app_tagline'.tr();
  static String get appSubtagline => 'app_subtagline'.tr();

  static String get loading => 'common.loading'.tr();
  static String get error => 'common.error'.tr();
  static String get success => 'common.success'.tr();
  static String get cancel => 'common.cancel'.tr();
  static String get confirm => 'common.confirm'.tr();
  static String get save => 'common.save'.tr();
  static String get delete => 'common.delete'.tr();
  static String get edit => 'common.edit'.tr();
  static String get back => 'common.back'.tr();
  static String get done => 'common.done'.tr();
  static String get ok => 'common.ok'.tr();
  static String get yes => 'common.yes'.tr();
  static String get no => 'common.no'.tr();
  static String get all => 'common.all'.tr();
  static String get search => 'common.search'.tr();
  static String get sort => 'common.sort'.tr();
  static String get newest => 'common.newest'.tr();
  static String get oldest => 'common.oldest'.tr();
  static String get nameAz => 'common.name_az'.tr();
  static String get nameZa => 'common.name_za'.tr();
  static String get priceLow => 'common.price_low'.tr();
  static String get priceHigh => 'common.price_high'.tr();
  static String get quantityLow => 'common.quantity_low'.tr();
  static String get quantityHigh => 'common.quantity_high'.tr();

  // ⭐ مفاتيح جديدة لقوة كلمة المرور
  static String get veryWeak => 'common.very_weak'.tr();
  static String get weak => 'common.weak'.tr();
  static String get medium => 'common.medium'.tr();
  static String get good => 'common.good'.tr();
  static String get strong => 'common.strong'.tr();
  static String get veryStrong => 'common.very_strong'.tr();
  static String get cameraUnavailable => 'common.camera_unavailable'.tr();
  static String get cameraError => 'common.camera_error'.tr();
  static String get flashError => 'common.flash_error'.tr();
  static String get cameraHint => 'common.camera_hint'.tr();
  static String get undo => 'common.undo'.tr();

  // ==================== دوال تسجيل الدخول ====================

  static String get loginTitle => 'login.title'.tr();
  static String get loginSubtitle => 'login.subtitle'.tr();
  static String get loginPhoneLabel => 'login.phone_label'.tr();
  static String get loginPhoneHint => 'login.phone_hint'.tr();
  static String get loginPhoneRequired => 'login.phone_required'.tr();
  static String get loginPhoneValid => 'login.phone_valid'.tr();
  static String get loginPasswordLabel => 'login.password_label'.tr();
  static String get loginPasswordHint => 'login.password_hint'.tr();
  static String get loginPasswordRequired => 'login.password_required'.tr();
  static String get loginPasswordMin => 'login.password_min'.tr();
  static String get loginRememberMe => 'login.remember_me'.tr();
  static String get loginForgotPassword => 'login.forgot_password'.tr();
  static String get loginSignIn => 'login.sign_in'.tr();
  static String get loginNoAccount => 'login.no_account'.tr();
  static String get loginRegisterNow => 'login.register_now'.tr();
  static String get loginError => 'login.error'.tr();

  // ⭐ مفاتيح جديدة لشاشة تسجيل الدخول
  static String get loginBlocked => 'login.blocked'.tr();
  static String loginBlockedMinutes(int minutes) =>
      'login.blocked_minutes'.tr().replaceAll('{minutes}', '$minutes');
  static String get loginAttemptsRemaining => 'login.attempts_remaining'.tr();
  static String get loginFeatureSales => 'login.feature_sales'.tr();
  static String get loginFeatureSalesDesc => 'login.feature_sales_desc'.tr();
  static String get loginFeatureBarcode => 'login.feature_barcode'.tr();
  static String get loginFeatureBarcodeDesc =>
      'login.feature_barcode_desc'.tr();
  static String get loginFeatureAnalytics => 'login.feature_analytics'.tr();
  static String get loginFeatureAnalyticsDesc =>
      'login.feature_analytics_desc'.tr();

  // ==================== دوال التسجيل ====================

  static String get registerTitle => 'register.title'.tr();
  static String get registerSubtitle => 'register.subtitle'.tr();
  static String get registerFullNameLabel => 'register.full_name_label'.tr();
  static String get registerFullNameHint => 'register.full_name_hint'.tr();
  static String get registerStoreNameLabel => 'register.store_name_label'.tr();
  static String get registerStoreNameHint => 'register.store_name_hint'.tr();
  static String get registerPhoneLabel => 'register.phone_label'.tr();
  static String get registerPhoneHint => 'register.phone_hint'.tr();
  static String get registerPasswordLabel => 'register.password_label'.tr();
  static String get registerPasswordHint => 'register.password_hint'.tr();
  static String get registerConfirmPasswordLabel =>
      'register.confirm_password_label'.tr();
  static String get registerConfirmPasswordHint =>
      'register.confirm_password_hint'.tr();
  static String get registerAgreeTerms => 'register.agree_terms'.tr();
  static String get registerTerms => 'register.terms'.tr();
  static String get registerAnd => 'register.and'.tr();
  static String get registerPrivacy => 'register.privacy'.tr();
  static String get registerCreateAccount => 'register.create_account'.tr();
  static String get registerHaveAccount => 'register.have_account'.tr();
  static String get registerSignIn => 'register.sign_in'.tr();
  static String get registerError => 'register.error'.tr();
  static String get registerErrorTerms => 'register.error_terms'.tr();
  static String get registerNameRequired => 'register.name_required'.tr();
  static String get registerStoreRequired => 'register.store_required'.tr();
  static String get registerPhoneRequired => 'register.phone_required'.tr();
  static String get registerPasswordRequired =>
      'register.password_required'.tr();
  static String get registerNameTooShort => 'register.name_too_short'.tr();
  static String get registerStoreTooShort => 'register.store_too_short'.tr();
  static String get registerPhoneValid => 'register.phone_valid'.tr();
  static String get registerPasswordMin => 'register.password_min'.tr();
  static String get registerConfirmRequired => 'register.confirm_required'.tr();
  static String get registerConfirmMatch => 'register.confirm_match'.tr();
  static String get registerSuccess => 'register.success'.tr();

  // ==================== دوال تسجيل الدخول عبر QR ====================

  static String get qrLoginButton => 'qr_login.button'.tr();
  static String get qrLoginButtonSubtitle => 'qr_login.button_subtitle'.tr();
  static String get qrLoginDialogTitle => 'qr_login.dialog_title'.tr();
  static String get qrLoginNote => 'qr_login.note'.tr();
  static String get qrLoginGenerate => 'qr_login.generate'.tr();
  static String get qrLoginTitle => 'qr_login.title'.tr();
  static String get qrLoginSubtitle => 'qr_login.subtitle'.tr();
  static String get qrLoginSigningIn => 'qr_login.signing_in'.tr();
  static String get qrLoginInvalidCode => 'qr_login.invalid_code'.tr();
  static String get qrLoginUpload => 'qr_login.upload'.tr();
  static String get qrLoginUploading => 'qr_login.uploading'.tr();
  static String get qrLoginUploadError => 'qr_login.upload_error'.tr();
  static String get qrLoginDownload => 'qr_login.download'.tr();
  static String get qrLoginDownloaded => 'qr_login.downloaded'.tr();
  static String get qrLoginDownloadError => 'qr_login.download_error'.tr();

  // ==================== دوال لوحة التحكم ====================

  static String get dashboardTitle => 'dashboard.title'.tr();
  static String get dashboardWelcome => 'dashboard.welcome'.tr();
  static String get dashboardTodayRevenue => 'dashboard.today_revenue'.tr();
  static String get dashboardVsYesterday => 'dashboard.vs_yesterday'.tr();
  static String get dashboardYesterday => 'dashboard.yesterday'.tr();
  static String get dashboardInventory => 'dashboard.inventory'.tr();
  static String get dashboardLowStock => 'dashboard.low_stock'.tr();
  static String get dashboardSalesToday => 'dashboard.sales_today'.tr();
  static String get dashboardTransactions => 'dashboard.transactions'.tr();
  static String get dashboardProducts => 'dashboard.products'.tr();
  static String get dashboardCategories => 'dashboard.categories'.tr();
  static String get dashboardCustomers => 'dashboard.customers'.tr();
  static String get dashboardActiveClients => 'dashboard.active_clients'.tr();
  static String get dashboardSalesOverview => 'dashboard.sales_overview'.tr();
  static String get dashboardTotal => 'dashboard.total'.tr();
  static String get dashboardWeekly => 'dashboard.weekly'.tr();
  static String get dashboardMonthly => 'dashboard.monthly'.tr();
  static String get dashboardYearly => 'dashboard.yearly'.tr();
  static String get dashboardSales => 'dashboard.sales'.tr();
  static String get dashboardRecentTransactions =>
      'dashboard.recent_transactions'.tr();
  static String get dashboardViewAll => 'dashboard.view_all'.tr();
  static String get dashboardNoTransactions => 'dashboard.no_transactions'.tr();
  static String get dashboardCompleteSale => 'dashboard.complete_sale'.tr();
  static String get dashboardCompleted => 'dashboard.completed'.tr();
  static String get dashboardJustNow => 'dashboard.just_now'.tr();
  static String get dashboardMinutesAgo => 'dashboard.minutes_ago'.tr();
  static String get dashboardHoursAgo => 'dashboard.hours_ago'.tr();
  static String get dashboardDaysAgo => 'dashboard.days_ago'.tr();
  static String get dashboardTransactionDetails =>
      'dashboard.transaction_details'.tr();
  static String get dashboardDate => 'dashboard.date'.tr();
  static String get dashboardTime => 'dashboard.time'.tr();
  static String get dashboardPayment => 'dashboard.payment'.tr();
  static String get dashboardTotalAmount => 'dashboard.total_amount'.tr();
  static String get dashboardProductsList => 'dashboard.products_list'.tr();
  static String get dashboardToday => 'dashboard.today'.tr();
  static String get dashboardAverageSales => 'dashboard.average_sales'.tr();
  static String get dashboardPerDay => 'dashboard.per_day'.tr();
  static String get dashboardLowStockTitle => 'dashboard.low_stock_title'.tr();
  static String get dashboardOutOfStock => 'dashboard.out_of_stock'.tr();
  static String get dashboardInStock => 'dashboard.in_stock'.tr();
  static String get dashboardInvoice => 'dashboard.invoice'.tr();

  // ⭐ مفاتيح جديدة لـ Dashboard
  static String get dashboardGoodMorning => 'dashboard.good_morning'.tr();
  static String get dashboardGoodAfternoon => 'dashboard.good_afternoon'.tr();
  static String get dashboardGoodEvening => 'dashboard.good_evening'.tr();
  static String get dashboardTopProducts => 'dashboard.top_products'.tr();
  static String get dashboardPaymentDistribution =>
      'dashboard.payment_distribution'.tr();
  static String get dashboardAverage => 'dashboard.average'.tr();
  static String get dashboardAlert => 'dashboard.alert'.tr();
  static String get dashboardExcellent => 'dashboard.excellent'.tr();

  // ==================== دوال POS ====================

  static String get posTitle => 'pos.title'.tr();
  static String get posSale => 'pos.sale'.tr();
  static String get posSearchHint => 'pos.search_hint'.tr();
  static String get posNoProducts => 'pos.no_products'.tr();
  static String get posNoResults => 'pos.no_results'.tr();
  static String get posNoResultsSub => 'pos.no_results_sub'.tr();
  static String get posProcessingSale => 'pos.processing_sale'.tr();
  static String get posPleaseWait => 'pos.please_wait'.tr();
  static String get posLoginAgain => 'pos.login_again'.tr();
  static String get posOutOfStock => 'pos.out_of_stock'.tr();
  static String get posAdded => 'pos.added'.tr();
  static String get posCart => 'pos.cart'.tr();
  static String get posEmptyCart => 'pos.empty_cart'.tr();
  static String get posStartShopping => 'pos.start_shopping'.tr();
  static String get posSubtotal => 'pos.subtotal'.tr();
  static String get posDiscount => 'pos.discount'.tr();
  static String get posTax => 'pos.tax'.tr();
  static String get posTotal => 'pos.total'.tr();
  static String get posHold => 'pos.hold'.tr();
  static String get posCheckout => 'pos.checkout'.tr();
  static String get posPaymentMethod => 'pos.payment_method'.tr();
  static String get posCash => 'pos.cash'.tr();
  static String get posCashSubtitle => 'pos.cash_subtitle'.tr();
  static String get posEdahabia => 'pos.edahabia'.tr();
  static String get posEdahabiaSubtitle => 'pos.edahabia_subtitle'.tr();
  static String get posRecommended => 'pos.recommended'.tr();
  static String get posConfirmSale => 'pos.confirm_sale'.tr();
  static String get posDateTime => 'pos.date_time'.tr();
  static String get posItems => 'pos.items'.tr();
  static String get posProductsTitle => 'pos.products_title'.tr();
  static String get posCancel => 'pos.cancel'.tr();
  static String get posCompleteSale => 'pos.complete_sale'.tr();
  static String get posSaleCompleted => 'pos.sale_completed'.tr();
  static String get posHoldOrder => 'pos.hold_order'.tr();
  static String get posOrderLabel => 'pos.order_label'.tr();
  static String get posSaveForLater => 'pos.save_for_later'.tr();
  static String get posLabel => 'pos.label'.tr();
  static String get posHeldOrders => 'pos.held_orders'.tr();
  static String get posNoHeldOrders => 'pos.no_held_orders'.tr();
  static String get posDeleteHeldTitle => 'pos.delete_held_title'.tr();
  static String get posDeleteHeldMessage => 'pos.delete_held_message'.tr();
  static String get posScanBarcode => 'pos.scan_barcode'.tr();
  static String get posEnterBarcode => 'pos.enter_barcode'.tr();
  static String get posScanProduct => 'pos.scan_product'.tr();
  static String get posProductNotFound => 'pos.product_not_found'.tr();
  static String get posScanError => 'pos.scan_error'.tr();
  static String get posRetryScan => 'pos.retry_scan'.tr();
  static String get posOutOfStockFeedback => 'pos.out_of_stock_feedback'.tr();
  static String get posItemRemoved => 'pos.item_removed'.tr();
  static String get posAddAsNew => 'pos.add_as_new'.tr();
  static String get posAddNew => 'pos.add_new'.tr();
  static String get posAddProduct => 'pos.add_product'.tr();
  static String get posEditProduct => 'pos.edit_product'.tr();
  static String get posProductName => 'pos.product_name'.tr();
  static String get posPrice => 'pos.price'.tr();
  static String get posQuantity => 'pos.quantity'.tr();
  static String get posBarcode => 'pos.barcode'.tr();
  static String get posEnterOrScan => 'pos.enter_or_scan'.tr();
  static String get posAdd => 'pos.add'.tr();
  static String get posUpdate => 'pos.update'.tr();
  static String get posAddProductShort => 'pos.add_product_short'.tr();
  static String get posUpdateProduct => 'pos.update_product'.tr();
  static String get posProductAdded => 'pos.product_added'.tr();
  static String get posProductUpdated => 'pos.product_updated'.tr();
  static String get posMultiScan => 'pos.multi_scan'.tr();
  static String get posMultiScanActive => 'pos.multi_scan_active'.tr();
  static String get posMultiScanDisable => 'pos.multi_scan_disable'.tr();
  static String get posAddScanned => 'pos.add_scanned'.tr();
  static String get posScannedBarcode => 'pos.scanned_barcode'.tr();
  static String get posNoBarcodes => 'pos.no_barcodes'.tr();
  static String get posAddedProducts => 'pos.added_products'.tr();
  static String get posNotFoundBarcodes => 'pos.not_found_barcodes'.tr();
  static String get posInvoiceOptions => 'pos.invoice_options'.tr();
  static String get posInvoiceChooseAction => 'pos.invoice_choose_action'.tr();
  static String get posInvoicePrint => 'pos.invoice_print'.tr();
  static String get posInvoicePrintSubtitle =>
      'pos.invoice_print_subtitle'.tr();
  static String get posInvoiceShare => 'pos.invoice_share'.tr();
  static String get posInvoiceShareSubtitle =>
      'pos.invoice_share_subtitle'.tr();
  static String get posInvoiceDownload => 'pos.invoice_download'.tr();
  static String get posInvoiceDownloadSubtitle =>
      'pos.invoice_download_subtitle'.tr();
  static String get posInvoiceClose => 'pos.invoice_close'.tr();
  static String get posDebt => 'pos.debt'.tr();
  static String get posDebtSubtitle => 'pos.debt_subtitle'.tr();

  // ==================== دوال المخزون ====================

  static String get inventoryTitle => 'inventory.title'.tr();
  static String get inventoryAdd => 'inventory.add'.tr();
  static String get inventorySearchHint => 'inventory.search_hint'.tr();
  static String get inventoryProductsCount => 'inventory.products_count'.tr();
  static String get inventoryItemsCount => 'inventory.items_count'.tr();
  static String get inventoryLowStock => 'inventory.low_stock'.tr();
  static String get inventoryNoProducts => 'inventory.no_products'.tr();
  static String get inventoryAddFirst => 'inventory.add_first'.tr();
  static String get inventoryAdjustSearch => 'inventory.adjust_search'.tr();
  static String get inventoryDeleteTitle => 'inventory.delete_title'.tr();
  static String get inventoryDeleteConfirm => 'inventory.delete_confirm'.tr();
  static String get inventoryDeleteWarning => 'inventory.delete_warning'.tr();
  static String get inventoryDelete => 'inventory.delete'.tr();
  static String get inventoryMinStock => 'inventory.min_stock'.tr();
  static String get inventoryMinStockRequired =>
      'inventory.min_stock_required'.tr();
  static String get inventoryCostPrice => 'inventory.cost_price'.tr();
  static String get inventoryCostPriceHint => 'inventory.cost_price_hint'.tr();
  static String get inventoryCost => 'inventory.cost'.tr();
  static String get inventoryNameRequired => 'inventory.name_required'.tr();
  static String get inventoryPriceRequired => 'inventory.price_required'.tr();
  static String get inventoryQuantityRequired =>
      'inventory.quantity_required'.tr();
  static String get inventoryDeleteLocalServer =>
      'inventory.delete_local_server'.tr();
  static String get inventoryDeleteServerFailed =>
      'inventory.delete_server_failed'.tr();
  static String get inventoryDeleteOffline => 'inventory.delete_offline'.tr();
  static String get inventoryLowStockAlert => 'inventory.low_stock_alert'.tr();
  static String get inventoryOutOfStockAlert =>
      'inventory.out_of_stock_alert'.tr();

  // ==================== دوال الإعدادات ====================

  static String get settingsTitle => 'settings.title'.tr();
  static String get settingsProfile => 'settings.profile'.tr();
  static String get settingsAppearance => 'settings.appearance'.tr();
  static String get settingsLightMode => 'settings.light_mode'.tr();
  static String get settingsLightSubtitle => 'settings.light_subtitle'.tr();
  static String get settingsDarkMode => 'settings.dark_mode'.tr();
  static String get settingsDarkSubtitle => 'settings.dark_subtitle'.tr();
  static String get settingsFollowSystem => 'settings.follow_system'.tr();
  static String get settingsFollowSubtitle => 'settings.follow_subtitle'.tr();
  static String get settingsGeneral => 'settings.general'.tr();
  static String get settingsNotifications => 'settings.notifications'.tr();
  static String get settingsNotificationsSubtitle =>
      'settings.notifications_subtitle'.tr();
  static String get settingsAutoSync => 'settings.auto_sync'.tr();
  static String get settingsAutoSyncSubtitle =>
      'settings.auto_sync_subtitle'.tr();
  static String get settingsBusiness => 'settings.business'.tr();
  static String get settingsLanguage => 'settings.language'.tr();
  static String get settingsLanguageChanged =>
      'settings.language_changed'.tr();
  static String get settingsCurrency => 'settings.currency'.tr();
  static String get settingsStoreInfo => 'settings.store_info'.tr();
  static String get settingsStoreInfoSubtitle =>
      'settings.store_info_subtitle'.tr();
  static String get settingsStoreName => 'settings.store_name'.tr();
  static String get settingsStorePhone => 'settings.store_phone'.tr();
  static String get settingsStorePhoneHint =>
      'settings.store_phone_hint'.tr();
  static String get settingsStoreAddress => 'settings.store_address'.tr();
  static String get settingsStoreAddressHint =>
      'settings.store_address_hint'.tr();
  static String get settingsTaxId => 'settings.tax_id'.tr();
  static String get settingsTaxIdHint => 'settings.tax_id_hint'.tr();
  static String get settingsStoreInfoSaved => 'settings.store_info_saved'.tr();
  static String get settingsStoreInfoError =>
      'settings.store_info_error'.tr();
  static String get settingsTaxSettings => 'settings.tax_settings'.tr();
  static String get settingsTaxSubtitle => 'settings.tax_subtitle'.tr();
  static String get settingsDangerZone => 'settings.danger_zone'.tr();
  static String get settingsLogout => 'settings.logout'.tr();
  static String get settingsDeleteAccount => 'settings.delete_account'.tr();
  static String get settingsLogoutConfirm => 'settings.logout_confirm'.tr();
  static String get settingsDeleteConfirm => 'settings.delete_confirm'.tr();
  static String get settingsDeleteWarning => 'settings.delete_warning'.tr();
  static String get settingsSelectLanguage => 'settings.select_language'.tr();
  static String get settingsEnglish => 'settings.english'.tr();
  static String get settingsArabic => 'settings.arabic'.tr();
  static String get settingsFrench => 'settings.french'.tr();

  // ==================== دوال الملف الشخصي ====================

  static String get profileTitle => 'profile.title'.tr();
  static String get profileUserInfo => 'profile.user_info'.tr();
  static String get profileStore => 'profile.store'.tr();
  static String get profileEmail => 'profile.email'.tr();
  static String get profileSubscription => 'profile.subscription'.tr();
  static String get profilePlan => 'profile.plan'.tr();
  static String get profileTrial => 'profile.trial'.tr();
  static String get profileBasic => 'profile.basic'.tr();
  static String get profilePremium => 'profile.premium'.tr();
  static String get profileEnterprise => 'profile.enterprise'.tr();
  static String get profileActive => 'profile.active'.tr();
  static String get profileExpired => 'profile.expired'.tr();
  static String get profileDaysRemaining => 'profile.days_remaining'.tr();
  static String get profileStartDate => 'profile.start_date'.tr();
  static String get profileEndDate => 'profile.end_date'.tr();
  static String get profileAutoRenew => 'profile.auto_renew'.tr();
  static String get profileEnabled => 'profile.enabled'.tr();
  static String get profileDisabled => 'profile.disabled'.tr();
  static String get profileNoSubscription => 'profile.no_subscription'.tr();
  static String get profileActiveSubscription =>
      'profile.active_subscription'.tr();
  static String get profileContactSupport => 'profile.contact_support'.tr();
  static String get profileOptions => 'profile.options'.tr();
  static String get profileRenew => 'profile.renew'.tr();
  static String get profileRenewSubtitle => 'profile.renew_subtitle'.tr();
  static String get profileSupport => 'profile.support'.tr();
  static String get profileSupportSubtitle => 'profile.support_subtitle'.tr();
  static String get profileContactInfo => 'profile.contact_info'.tr();
  static String get profileClose => 'profile.close'.tr();

  // ==================== دوال انتهاء الاشتراك ====================

  static String get expiredTitle => 'subscription_expired.title'.tr();
  static String get expiredMessage => 'subscription_expired.message'.tr();
  static String get expiredViewProfile =>
      'subscription_expired.view_profile'.tr();
  static String get expiredLogout => 'subscription_expired.logout'.tr();

  // ==================== دوال Bottom Navigation Bar ====================

  static String get bottomDashboard => 'bottom.dashboard'.tr();
  static String get bottomPos => 'bottom.pos'.tr();
  static String get bottomInventory => 'bottom.inventory'.tr();
  static String get bottomSalesHistory => 'bottom.sales_history'.tr();

  // ==================== دوال المزامنة (Sync) ====================

  static String get syncPreparing => 'sync.preparing'.tr();
  static String get syncJustNow => 'sync.just_now'.tr();
  static String syncPendingItems(int count) =>
      'sync.pending_items'.tr().replaceAll('{count}', '$count');
  static String get syncUploading => 'sync.uploading'.tr();
  static String get syncDownloading => 'sync.downloading'.tr();
  static String get syncCompleted => 'sync.completed'.tr();
  static String get syncError => 'sync.error'.tr();
  static String get syncConflict => 'sync.conflict'.tr();
  static String get syncNoInternet => 'sync.no_internet'.tr();
  static String get syncRetry => 'sync.retry'.tr();
  static String get syncClearErrors => 'sync.clear_errors'.tr();
  static String get syncErrorsTitle => 'sync.errors_title'.tr();
  static String get syncNoErrors => 'sync.no_errors'.tr();
  static String get syncConflictTitle => 'sync.conflict_title'.tr();
  static String get syncConflictMessage => 'sync.conflict_message'.tr();
  static String get syncConflictInfo => 'sync.conflict_info'.tr();
  static String get syncProcessingProduct => 'sync.processing_product'.tr();
  static String get syncProcessingSale => 'sync.processing_sale'.tr();
  static String get syncTapToView => 'sync.tap_to_view'.tr();
  static String get syncErrorType => 'sync.error_type'.tr();
  static String get syncErrorId => 'sync.error_id'.tr();
  static String get syncErrorTime => 'sync.error_time'.tr();
  static String get syncUnknownError => 'sync.unknown_error'.tr();

  // ==================== دوال سجل المبيعات (Sales History) ====================

  static String get salesHistoryTitle => 'sales_history.title'.tr();
  static String get salesHistoryEmpty => 'sales_history.empty'.tr();
  static String get salesHistoryEmptySub => 'sales_history.empty_sub'.tr();
  static String get salesHistoryNoResults => 'sales_history.no_results'.tr();
  static String get salesHistoryNoResultsSub =>
      'sales_history.no_results_sub'.tr();
  static String get salesHistorySearchHint => 'sales_history.search_hint'.tr();
  static String get salesHistoryFilterAll => 'sales_history.filter_all'.tr();
  static String get salesHistoryFilterSales =>
      'sales_history.filter_sales'.tr();
  static String get salesHistoryFilterReturns =>
      'sales_history.filter_returns'.tr();
  static String get salesHistoryTotal => 'sales_history.total'.tr();
  static String get salesHistorySales => 'sales_history.sales'.tr();
  static String get salesHistoryReturns => 'sales_history.returns'.tr();
  static String get salesHistoryReturn => 'sales_history.return'.tr();
  static String get salesHistoryReturnProduct =>
      'sales_history.return_product'.tr();
  static String get salesHistoryReturnTitle =>
      'sales_history.return_title'.tr();
  static String get salesHistoryReturnConfirm =>
      'sales_history.return_confirm'.tr();
  static String get salesHistoryReturnSuccess =>
      'sales_history.return_success'.tr();
  static String get salesHistoryReturnError =>
      'sales_history.return_error'.tr();
  static String get salesHistoryReturning =>
      'sales_history.returning'.tr();
  static String get salesHistorySelectProducts =>
      'sales_history.select_products'.tr();
  static String get salesHistorySelectProductsSub =>
      'sales_history.select_products_sub'.tr();
  static String get salesHistoryPreview => 'sales_history.preview'.tr();
  static String get salesHistoryPreviewTitle =>
      'sales_history.preview_title'.tr();
  static String get salesHistoryInvoice => 'sales_history.invoice'.tr();
  static String get salesHistoryCustomer => 'sales_history.customer'.tr();
  static String get salesHistoryPayment => 'sales_history.payment'.tr();
  static String get salesHistoryDate => 'sales_history.date'.tr();
  static String get salesHistoryTotalAmount =>
      'sales_history.total_amount'.tr();
  static String get salesHistorySubtotal => 'sales_history.subtotal'.tr();
  static String get salesHistoryDiscount => 'sales_history.discount'.tr();
  static String get salesHistoryTax => 'sales_history.tax'.tr();
  static String get salesHistoryReturnBadge =>
      'sales_history.return_badge'.tr();
  static String get salesHistoryProductQuantity =>
      'sales_history.product_quantity'.tr();

  // ⭐ مفاتيح جديدة لسجل المبيعات (المرتجعات المحسنة)
  static String get salesHistoryCannotReturn =>
      'sales_history.cannot_return'.tr();
  static String get salesHistoryAllReturned =>
      'sales_history.all_returned'.tr();
  static String get salesHistoryAvailableQuantity =>
      'sales_history.available_quantity'.tr();
  static String get salesHistoryReturnTotal =>
      'sales_history.return_total'.tr();
  static String get salesHistoryRemainingAmount =>
      'sales_history.remaining_amount'.tr();
  static String get salesHistoryStatus => 'sales_history.status'.tr();
  static String get salesHistoryFullyReturned =>
      'sales_history.fully_returned'.tr();
  static String get salesHistoryPartiallyReturned =>
      'sales_history.partially_returned'.tr();
  static String get salesHistoryReturned => 'sales_history.returned'.tr();
  static String get salesHistoryLoadMore => 'sales_history.load_more'.tr();

  // ==================== دوال القائمة الجانبية (Menu) ====================

  static String get menuNavigation => 'menu.navigation'.tr();
  static String get menuSectionManage => 'menu.section_manage'.tr();
  static String get menuSectionApp => 'menu.section_app'.tr();
  static String get menuVersion => 'menu.version'.tr();
  static String get menuAppVersion => 'menu.app_version'.tr();

  // ==================== دوال الموردين والمشتريات ====================
  static String get suppliersTitle => 'suppliers.title'.tr();
  static String get customersTitle => 'customers.title'.tr();
  static String get purchasesTitle => 'purchases.title'.tr();
  static String get reportsTitle => 'reports.title'.tr();

  // ==================== دوال المبيعات (Sale) ====================
  static String get saleDeleteTitle => 'sale.delete_title'.tr();
  static String get saleDeleteConfirm => 'sale.delete_confirm'.tr();
  static String get saleDeleted => 'sale.deleted'.tr();
  static String get saleDeleteError => 'sale.delete_error'.tr();
  static String get saleReturn => 'sale.return'.tr();

  // ==================== دوال عامة إضافية ====================
  static String get general => 'common.general'.tr();
  static String get view => 'common.view'.tr();
  static String order(int count) =>
      'common.order'.tr(namedArgs: {'count': '$count'});
  static String days(int count) =>
      'common.days'.tr(namedArgs: {'count': '$count'});
  static String get brandName => 'common.brand_name'.tr();
  static String get posBadge => 'common.pos_badge'.tr();
  static String get noInternet => 'common.no_internet'.tr();
  static String get noUserLoggedIn => 'common.no_user_logged_in'.tr();
  static String get noFirebaseSession => 'common.no_firebase_session'.tr();
  static String get defaultStoreAdmin =>
      'settings.default_store_admin'.tr();
  static String get defaultStoreName => 'settings.default_store_name'.tr();

  // ==================== دوال الأخطاء (Auth) ====================
  static String get authFirebaseUnavailable =>
      'auth.firebase_unavailable'.tr();
  static String get authLoginError => 'auth.login_error'.tr();
  static String get authRegisterError => 'auth.register_error'.tr();
  static String get authUserNotFound => 'auth.user_not_found'.tr();
  static String get authWrongPassword => 'auth.wrong_password'.tr();
  static String get authTooManyRequests => 'auth.too_many_requests'.tr();
  static String get authNetworkFailed => 'auth.network_failed'.tr();
  static String get authInvalidEmail => 'auth.invalid_email'.tr();
  static String get authEmailInUse => 'auth.email_in_use'.tr();
  static String get authWeakPassword => 'auth.weak_password'.tr();
  static String get authUserNotAuthenticated =>
      'auth.user_not_authenticated'.tr();
  // ⭐ رسالة موحّدة لعدم كشف وجود الحساب (منع تعداد المستخدمين)
  static String get authInvalidCredentials => 'auth.invalid_credentials'.tr();
  static String get authPasswordChangeError => 'auth.password_change_error'.tr();
  static String get authPasswordTooWeak => 'auth.password_too_weak'.tr();

  // ==================== دوال الدفع ====================
  static String get paymentCash => 'payment.cash'.tr();
  static String get paymentEdahabia => 'payment.edahabia'.tr();
  static String get paymentDebt => 'payment.debt'.tr();
  static String get customersCredit => 'customers.credit'.tr();
  static String get customersName => 'customers.name'.tr();
  static String get customersPaidNow => 'customers.paidNow'.tr();
  static String get customersPaymentAmount => 'customers.paymentAmount'.tr();
  static String get dashboardWalkIn => 'dashboard.walk_in'.tr();

  // ⭐ تحويل طريقة الدفع المخزنة إلى نص مترجم
  static String paymentMethod(String raw) {
    switch (raw) {
      case 'Cash':
        return paymentCash;
      case 'Edahabia/CIB':
        return paymentEdahabia;
      case 'Debt':
        return paymentDebt;
      default:
        return raw;
    }
  }

  // ⭐ تحويل الفئة المخزنة إلى نص مترجم (All / General)
  static String categoryLabel(String raw) {
    if (raw == 'All') return all;
    if (raw == 'General') return general;
    return raw;
  }

  // ==================== دوال الطباعة (Invoice) ====================
  static String get printingTitle => 'printing.title'.tr();
  static String printingInvoiceNo(String id) =>
      'printing.invoice_no'.tr(namedArgs: {'id': id});
  static String printingDate(String date) =>
      'printing.date'.tr(namedArgs: {'date': date});
  static String printingTime(String time) =>
      'printing.time'.tr(namedArgs: {'time': time});
  static String get printingPaid => 'printing.paid'.tr();
  static String get printingProduct => 'printing.product'.tr();
  static String get printingQty => 'printing.qty'.tr();
  static String get printingPrice => 'printing.price'.tr();
  static String get printingTotal => 'printing.total'.tr();
  static String printingSubtotal(String value) =>
      'printing.subtotal'.tr(namedArgs: {'value': value});
  static String printingDiscount(String value) =>
      'printing.discount'.tr(namedArgs: {'value': value});
  static String printingTax(String value) =>
      'printing.tax'.tr(namedArgs: {'value': value});
  static String printingTotalLabel(String value) =>
      'printing.total_label'.tr(namedArgs: {'value': value});
  static String printingPayment(String method) =>
      'printing.payment'.tr(namedArgs: {'method': method});
  static String get printingThankYou => 'printing.thank_you'.tr();
  static String get printingVisitAgain => 'printing.visit_again'.tr();
  static String get printingCustomerLabel => 'printing.customer'.tr();
  static String get printingPhoneLabel => 'printing.phone'.tr();
  static String get printingSubtotalLabel => 'printing.subtotal_label'.tr();
  static String get printingDiscountLabel => 'printing.discount_label'.tr();
  static String get printingTaxLabel => 'printing.tax_label'.tr();
  static String get printingTotalText => 'printing.total_text'.tr();
  static String get printingTaxIdLabel => 'printing.tax_id'.tr();

  // ==================== دوال تسجيل الدخول - الموافقة ====================

  static String get loginAgreePrefix => 'login.agree_prefix'.tr();
  static String get loginAgreePrivacy => 'login.agree_privacy'.tr();
  static String get loginAgreeAnd => 'login.agree_and'.tr();
  static String get loginAgreeTerms => 'login.agree_terms'.tr();

  // ==================== دوال سياسة الخصوصية ====================

  static String get privacyTitle => 'privacy_policy.title'.tr();
  static String privacyLastUpdated(String date) =>
      'privacy_policy.last_updated'.tr(namedArgs: {'date': date});
  static String get privacyIntroTitle => 'privacy_policy.intro_title'.tr();
  static String get privacyIntroBody => 'privacy_policy.intro_body'.tr();
  static String get privacyCollectTitle => 'privacy_policy.collect_title'.tr();
  static String get privacyCollectBody => 'privacy_policy.collect_body'.tr();
  static String get privacyUseTitle => 'privacy_policy.use_title'.tr();
  static String get privacyUseBody => 'privacy_policy.use_body'.tr();
  static String get privacyStorageTitle => 'privacy_policy.storage_title'.tr();
  static String get privacyStorageBody => 'privacy_policy.storage_body'.tr();
  static String get privacyCameraTitle => 'privacy_policy.camera_title'.tr();
  static String get privacyCameraBody => 'privacy_policy.camera_body'.tr();
  static String get privacySharingTitle => 'privacy_policy.sharing_title'.tr();
  static String get privacySharingBody => 'privacy_policy.sharing_body'.tr();
  static String get privacySecurityTitle => 'privacy_policy.security_title'.tr();
  static String get privacySecurityBody => 'privacy_policy.security_body'.tr();
  static String get privacyRetentionTitle => 'privacy_policy.retention_title'.tr();
  static String get privacyRetentionBody => 'privacy_policy.retention_body'.tr();
  static String get privacyRightsTitle => 'privacy_policy.rights_title'.tr();
  static String get privacyRightsBody => 'privacy_policy.rights_body'.tr();
  static String get privacyChildrenTitle => 'privacy_policy.children_title'.tr();
  static String get privacyChildrenBody => 'privacy_policy.children_body'.tr();
  static String get privacyChangesTitle => 'privacy_policy.changes_title'.tr();
  static String get privacyChangesBody => 'privacy_policy.changes_body'.tr();
  static String get privacyContactTitle => 'privacy_policy.contact_title'.tr();
  static String get privacyContactBody => 'privacy_policy.contact_body'.tr();

  // ==================== دوال الشروط والأحكام ====================

  static String get termsTitle => 'terms.title'.tr();
  static String termsLastUpdated(String date) =>
      'terms.last_updated'.tr(namedArgs: {'date': date});
  static String get termsIntroTitle => 'terms.intro_title'.tr();
  static String get termsIntroBody => 'terms.intro_body'.tr();
  static String get termsServiceTitle => 'terms.service_title'.tr();
  static String get termsServiceBody => 'terms.service_body'.tr();
  static String get termsAccountTitle => 'terms.account_title'.tr();
  static String get termsAccountBody => 'terms.account_body'.tr();
  static String get termsSubscriptionTitle => 'terms.subscription_title'.tr();
  static String get termsSubscriptionBody => 'terms.subscription_body'.tr();
  static String get termsUseTitle => 'terms.use_title'.tr();
  static String get termsUseBody => 'terms.use_body'.tr();
  static String get termsAccuracyTitle => 'terms.accuracy_title'.tr();
  static String get termsAccuracyBody => 'terms.accuracy_body'.tr();
  static String get termsIpTitle => 'terms.ip_title'.tr();
  static String get termsIpBody => 'terms.ip_body'.tr();
  static String get termsPrivacyTitle => 'terms.privacy_title'.tr();
  static String get termsPrivacyBody => 'terms.privacy_body'.tr();
  static String get termsLiabilityTitle => 'terms.liability_title'.tr();
  static String get termsLiabilityBody => 'terms.liability_body'.tr();
  static String get termsTerminationTitle => 'terms.termination_title'.tr();
  static String get termsTerminationBody => 'terms.termination_body'.tr();
  static String get termsChangesTitle => 'terms.changes_title'.tr();
  static String get termsChangesBody => 'terms.changes_body'.tr();
  static String get termsLawTitle => 'terms.law_title'.tr();
  static String get termsLawBody => 'terms.law_body'.tr();
  static String get termsContactTitle => 'terms.contact_title'.tr();
  static String get termsContactBody => 'terms.contact_body'.tr();

  // ==================== دوال التواريخ ====================
  static String dayName(int weekday) {
    // Dart weekday: Monday=1 ... Sunday=7 — الترتيب يبدأ بالإثنين
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday'
    ];
    return 'dates.${names[weekday - 1]}'.tr();
  }

  static String shortDayName(int weekday) {
    const names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    return 'dates.short_${names[weekday - 1]}'.tr();
  }

  static String shortMonthName(int month) {
    const names = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec'
    ];
    return 'dates.short_${names[month - 1]}'.tr();
  }

  static String formatHeaderDate(
      String dayName, int day, int month, int year) {
    return 'dates.header_format'.tr(namedArgs: {
      'dayName': dayName,
      'day': day.toString().padLeft(2, '0'),
      'month': month.toString().padLeft(2, '0'),
      'year': '$year',
    });
  }

  static String weekShort(int weekNumber) {
    return 'dates.week_short'.tr(namedArgs: {'number': '$weekNumber'});
  }

  // ==================== الوحدات ====================
  static String unitLabel(String unit) =>
      'unit.${unit == 'kg' ? 'kg' : unit == 'litre' ? 'liter' : 'piece'}'.tr();

  // ⭐ مفاتيح مؤقتة للمشتريات/الموردين (تُستبدل بمفاتيح .tr() في Task 7)
  static String get purchasesEmptyCart => 'purchases.emptyCart'.tr();
  static String get purchasesOriginalNotFound => 'purchases.originalNotFound'.tr();
  static String get purchasesAlreadyFullyReturned => 'purchases.alreadyFullyReturned'.tr();
  static String get purchasesReturnExceedsCap => 'purchases.exceedsCap'.tr();
  static String get purchasesProductNotFound => 'purchases.productNotFound'.tr();
  static String get purchasesInsufficientStock => 'purchases.insufficientStock'.tr();
  static String get purchasesDeleteBlockedNegative => 'purchases.deleteBlockedNegative'.tr();
  static String get purchasesPurchaseNotFound => 'purchases.purchaseNotFound'.tr();
  static String get purchasesCannotReturnFromReturn =>
      'purchases.cannotReturnFromReturn'.tr();
  static String get purchasesPurchaseAlreadyFullyReturned =>
      'purchases.purchaseAlreadyFullyReturned'.tr();

  // ==================== رسائل أخطاء عامة ====================
  static String get commonUnknown => 'common.unknown'.tr();
  static String get commonPrintFailed => 'common.print_failed'.tr();
  static String get commonReceipt => 'common.receipt'.tr();
  static String get commonPhonePlaceholder => 'common.phone_placeholder'.tr();
  static String get commonThousandSuffix => 'common.thousand_suffix'.tr();
  static String get commonMillionSuffix => 'common.million_suffix'.tr();
  static String commonTimedOut(int seconds) =>
      'common.timed_out'.tr(namedArgs: {'seconds': '$seconds'});

  // ==================== المبيعات: أخطاء الإرجاع ====================
  static String get salesHistorySaleNotFound =>
      'sales_history.sale_not_found'.tr();
  static String get salesHistoryCannotReturnFromReturn =>
      'sales_history.cannot_return_from_return'.tr();
  static String get salesHistoryAlreadyFullyReturned =>
      'sales_history.already_fully_returned'.tr();

  // ==================== نقطة البيع: نافذة الدفع الجزئي ====================
  static String get posPaidNowInvalidNumber =>
      'pos.paid_now_invalid_number'.tr();
  static String get posPaidNowNegative => 'pos.paid_now_negative'.tr();
  static String posPaidNowExceedsTotal(String total) =>
      'pos.paid_now_exceeds_total'.tr(namedArgs: {'total': total});
  static String get posPaidNowPayLater => 'pos.paid_now_pay_later'.tr();
  static String get posPaidNowConfirm => 'pos.paid_now_confirm'.tr();
  static String get posPaidOnPurchase => 'pos.paid_on_purchase'.tr();

  // ==================== العملاء: حالات فراغ ====================
  static String get customersNoDebts => 'customers.noDebts'.tr();
  static String get customersNoTransactions => 'customers.noTransactions'.tr();

  // ==================== رمز QR: تحذيرات وأخطاء ====================
  static String get qrLoginSecurityWarning => 'qr_login.security_warning'.tr();
  static String get qrLoginPermanentNote => 'qr_login.permanent_note'.tr();
  static String get qrLoginRegenerate => 'qr_login.regenerate'.tr();
  static String get qrLoginRegenerateTitle => 'qr_login.regenerate_title'.tr();
  static String get qrLoginRegenerateBody => 'qr_login.regenerate_body'.tr();
  static String get qrLoginNotRendered => 'qr_login.not_rendered'.tr();
  static String get qrLoginEncodeFailed => 'qr_login.encode_failed'.tr();
  static String get qrLoginInvalidSalt => 'qr_login.invalid_salt'.tr();

  // ==================== المصادقة ====================
  static String get authRegistrationNoUser => 'auth.registration_no_user'.tr();
}
