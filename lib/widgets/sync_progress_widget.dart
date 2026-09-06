// lib/widgets/sync_progress_widget.dart

import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../helpers/localization_helper.dart';

/// ويدجيت لعرض تقدم المزامنة
class SyncProgressWidget extends StatefulWidget {
  final VoidCallback? onTap;
  final bool showAsFloating;

  const SyncProgressWidget({
    super.key,
    this.onTap,
    this.showAsFloating = false,
  });

  @override
  State<SyncProgressWidget> createState() => _SyncProgressWidgetState();
}

class _SyncProgressWidgetState extends State<SyncProgressWidget> {
  final SyncService _sync = SyncService();
  SyncStatus _status = SyncStatus.idle;
  SyncProgress _progress = SyncProgress();
  List<Map<String, dynamic>> _errors = [];
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _status = _sync.syncStatusNotifier.value;
    _progress = _sync.syncProgressNotifier.value;
    _errors = _sync.syncErrors;
    _isOnline = _sync.isOnline;

    _sync.syncStatusNotifier.addListener(_onStatusChanged);
    _sync.syncProgressNotifier.addListener(_onProgressChanged);
  }

  @override
  void dispose() {
    _sync.syncStatusNotifier.removeListener(_onStatusChanged);
    _sync.syncProgressNotifier.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onStatusChanged() {
    setState(() {
      _status = _sync.syncStatusNotifier.value;
      _isOnline = _sync.isOnline;
    });
  }

  void _onProgressChanged() {
    setState(() {
      _progress = _sync.syncProgressNotifier.value;
      _errors = _sync.syncErrors;
      _isOnline = _sync.isOnline;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;

    // ⭐ إذا كان هناك خطأ في المزامنة بسبب عدم وجود إنترنت
    if (!_isOnline && _status == SyncStatus.error) {
      return _buildNoInternetIndicator(isDark, accentColor);
    }

    // ⭐ إذا كانت المزامنة في وضع الخمول ولا يوجد تقدم، نختفي
    if (_status == SyncStatus.idle && _progress.progress == 0.0) {
      return const SizedBox.shrink();
    }

    // ⭐ إذا كانت المزامنة ناجحة، نعرض إشعار نجاح لمدة 3 ثواني
    if (_status == SyncStatus.success) {
      return TickerMode(
        enabled: true,
        child: _AutoDismissibleWidget(
          // ⭐ key حسب الحالة: يمنع إعادة استخدام العنصر بين فرعين
          // مختلفين (وإلا بقي _isVisible=false وأُخفي المؤشر التالي للأبد)
          key: ValueKey('auto_dismiss_$_status'),
          duration: const Duration(seconds: 3),
          child: _buildSuccessIndicator(isDark, accentColor),
        ),
      );
    }

    // ⭐ إذا كان هناك خطأ (غير ناتج عن عدم إنترنت)
    if (_status == SyncStatus.error && _isOnline) {
      return _buildErrorIndicator(isDark, accentColor);
    }

    // ⭐ المزامنة جارية
    return _buildSyncProgressIndicator(isDark, accentColor);
  }

  // ⭐ مؤشر عدم وجود إنترنت (يظهر لفترة قصيرة ثم يختفي)
  Widget _buildNoInternetIndicator(bool isDark, Color accentColor) {
    final child = widget.showAsFloating
        ? _buildFloatingContainer(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationHelper.syncNoInternet,
                    style: AppTextStyles.bodyMedium(
                      color: isDark
                          ? AppColors.textDarkPrimary
                          : AppColors.textLightPrimary,
                    ),
                  ),
                ),
              ],
            ),
          )
        : _buildContainer(
            isDark: isDark,
            accentColor: AppColors.warning,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationHelper.syncNoInternet,
                    style: AppTextStyles.bodyMedium(
                      color: isDark
                          ? AppColors.textDarkPrimary
                          : AppColors.textLightPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );

    return TickerMode(
      enabled: true,
      child: _AutoDismissibleWidget(
        // ⭐ key حسب الحالة (انظر فرع النجاح أعلاه)
        key: ValueKey('auto_dismiss_$_status'),
        duration: const Duration(seconds: 3),
        child: child,
      ),
    );
  }

  Widget _buildSyncProgressIndicator(bool isDark, Color accentColor) {
    final progress = _progress.progress.clamp(0.0, 1.0);
    final totalItems = _progress.totalProducts + _progress.totalSales;
    final syncedItems = _progress.syncedProducts + _progress.syncedSales;
    final hasProgressInfo =
        totalItems > 0 || _progress.progress > 0.0;

    String actionText = _progress.currentAction;
    if (actionText.isEmpty) {
      actionText = LocalizationHelper.syncPreparing;
    }

    return widget.showAsFloating
        ? _buildFloatingContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? AppColors.white : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocalizationHelper.loading,
                            style: AppTextStyles.bodyMedium(
                              color: isDark
                                  ? AppColors.textDarkPrimary
                                  : AppColors.textLightPrimary,
                            ),
                          ),
                          if (actionText.isNotEmpty)
                            Text(
                              actionText,
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.textDarkTertiary
                                    : AppColors.textLightTertiary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hasProgressInfo ? progress : null,
                    minHeight: 4,
                    backgroundColor: isDark
                        ? AppColors.grey700.withValues(alpha:0.3)
                        : AppColors.grey200,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (hasProgressInfo)
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.textDarkTertiary
                              : AppColors.textLightTertiary,
                          fontSize: 11,
                        ),
                      ),
                    if (totalItems > 0)
                      Text(
                        ' • $syncedItems/$totalItems',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.textDarkTertiary
                              : AppColors.textLightTertiary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          )
        : _buildContainer(
            isDark: isDark,
            accentColor: accentColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? AppColors.white : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocalizationHelper.loading,
                            style: AppTextStyles.bodyMedium(
                              color: isDark
                                  ? AppColors.textDarkPrimary
                                  : AppColors.textLightPrimary,
                            ),
                          ),
                          if (actionText.isNotEmpty)
                            Text(
                              actionText,
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.textDarkTertiary
                                    : AppColors.textLightTertiary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hasProgressInfo ? progress : null,
                    minHeight: 4,
                    backgroundColor: isDark
                        ? AppColors.grey700.withValues(alpha:0.3)
                        : AppColors.grey200,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (hasProgressInfo)
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.textDarkTertiary
                              : AppColors.textLightTertiary,
                          fontSize: 11,
                        ),
                      ),
                    if (totalItems > 0)
                      Text(
                        ' • $syncedItems/$totalItems',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.textDarkTertiary
                              : AppColors.textLightTertiary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
  }

  Widget _buildSuccessIndicator(bool isDark, Color accentColor) {
    return widget.showAsFloating
        ? _buildFloatingContainer(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationHelper.syncCompleted,
                    style: AppTextStyles.bodyMedium(
                      color: isDark
                          ? AppColors.textDarkPrimary
                          : AppColors.textLightPrimary,
                    ),
                  ),
                ),
              ],
            ),
          )
        : _buildContainer(
            isDark: isDark,
            accentColor: AppColors.success,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationHelper.syncCompleted,
                    style: AppTextStyles.bodyMedium(
                      color: isDark
                          ? AppColors.textDarkPrimary
                          : AppColors.textLightPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  Widget _buildErrorIndicator(bool isDark, Color accentColor) {
    final errorCount = _errors.length;

    return widget.showAsFloating
        ? _buildFloatingContainer(
            child: InkWell(
              onTap: widget.onTap ?? _showErrorDialog,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocalizationHelper.syncError,
                          style: AppTextStyles.bodyMedium(
                            color: isDark
                                ? AppColors.textDarkPrimary
                                : AppColors.textLightPrimary,
                          ),
                        ),
                        Text(
                          errorCount > 1
                              ? '$errorCount ${LocalizationHelper.syncErrorsTitle.toLowerCase()}'
                              : (_errors.isNotEmpty
                                  ? _errors.last['message'] as String? ??
                                      LocalizationHelper.syncUnknownError
                                  : LocalizationHelper.syncNoErrors),
                          style: AppTextStyles.caption(
                            color: AppColors.error,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.grey500 : AppColors.grey400,
                    size: 18,
                  ),
                ],
              ),
            ),
          )
        : _buildContainer(
            isDark: isDark,
            accentColor: AppColors.error,
            child: InkWell(
              onTap: widget.onTap ?? _showErrorDialog,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocalizationHelper.syncError,
                          style: AppTextStyles.bodyMedium(
                            color: isDark
                                ? AppColors.textDarkPrimary
                                : AppColors.textLightPrimary,
                          ),
                        ),
                        Text(
                          errorCount > 1
                              ? '$errorCount ${LocalizationHelper.syncErrorsTitle.toLowerCase()}'
                              : (_errors.isNotEmpty
                                  ? _errors.last['message'] as String? ??
                                      LocalizationHelper.syncUnknownError
                                  : LocalizationHelper.syncNoErrors),
                          style: AppTextStyles.caption(
                            color: AppColors.error,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.grey500 : AppColors.grey400,
                    size: 18,
                  ),
                ],
              ),
            ),
          );
  }

  Widget _buildContainer({
    required bool isDark,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha:0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? AppColors.shadowColorDark : AppColors.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildFloatingContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.shadowColorDark
                : AppColors.shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 2,
          ),
        ],
      ),
      child: child,
    );
  }

  void _showErrorDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error_rounded,
                  color: AppColors.error, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              LocalizationHelper.syncErrorsTitle,
              style: TextStyle(
                  color: titleColor, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: _errors.isEmpty
            ? Text(LocalizationHelper.syncNoErrors,
                style: TextStyle(color: bodyColor))
            : SizedBox(
                width: double.maxFinite,
                height: 200,
                child: ListView.separated(
                  itemCount: _errors.length,
                  separatorBuilder: (_, __) => Divider(
                    color: isDark
                        ? AppColors.grey700.withValues(alpha:0.3)
                        : AppColors.grey200,
                  ),
                  itemBuilder: (_, i) {
                    final error = _errors[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            error['message'] as String? ??
                                LocalizationHelper.syncUnknownError,
                            style:
                                TextStyle(color: AppColors.error, fontSize: 13),
                          ),
                          if (error['type'] != null)
                            Text(
                              '${LocalizationHelper.syncErrorType}: ${error['type']}, ${LocalizationHelper.syncErrorId}: ${error['id'] ?? LocalizationHelper.commonUnknown}',
                              style: TextStyle(color: bodyColor, fontSize: 11),
                            ),
                          if (error['timestamp'] != null)
                            Text(
                              '${LocalizationHelper.syncErrorTime}: ${error['timestamp']}',
                              style: TextStyle(
                                  color: AppColors.grey500, fontSize: 11),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () {
              _sync.clearErrors();
              Navigator.pop(ctx);
            },
            child: Text(
              LocalizationHelper.syncClearErrors,
              style: TextStyle(color: AppColors.grey500),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _sync.syncNow();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: Text(LocalizationHelper.syncRetry),
          ),
        ],
      ),
    );
  }
}

/// ⭐ Widget يقوم بإخفاء نفسه تلقائياً بعد مدة محددة
class _AutoDismissibleWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const _AutoDismissibleWidget({
    super.key,
    required this.child,
    required this.duration,
  });

  @override
  State<_AutoDismissibleWidget> createState() => _AutoDismissibleWidgetState();
}

class _AutoDismissibleWidgetState extends State<_AutoDismissibleWidget>
    with SingleTickerProviderStateMixin {
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isVisible ? widget.child : const SizedBox.shrink();
  }
}
