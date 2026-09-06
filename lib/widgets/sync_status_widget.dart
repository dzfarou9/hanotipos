// lib/widgets/sync_status_widget.dart

import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../helpers/localization_helper.dart';

/// ويدجيت يعرض حالة المزامنة في شريط التطبيق
class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({
    super.key,
    this.showAsFloating = false,
    this.onTap,
  });

  final bool showAsFloating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final syncService = SyncService();

    return ValueListenableBuilder<SyncStatus>(
      valueListenable: syncService.syncStatusNotifier,
      builder: (context, status, _) {
        // لا نظهر الويجت إذا كانت المزامنة غير نشطة ولا توجد عناصر معلقة
        if (status == SyncStatus.idle && syncService.pendingSyncCount == 0) {
          return const SizedBox.shrink();
        }

        Color indicatorColor;
        IconData indicatorIcon;
        String tooltip;

        switch (status) {
          case SyncStatus.syncing:
            indicatorColor = AppColors.warning;
            indicatorIcon = Icons.sync_rounded;
            tooltip = LocalizationHelper.syncUploading;
            break;
          case SyncStatus.success:
            indicatorColor = AppColors.success;
            indicatorIcon = Icons.cloud_done_rounded;
            tooltip = LocalizationHelper.syncCompleted;
            break;
          case SyncStatus.error:
            indicatorColor = AppColors.error;
            indicatorIcon = Icons.cloud_off_rounded;
            tooltip = LocalizationHelper.syncError;
            break;
          default:
            if (syncService.pendingSyncCount > 0) {
              indicatorColor = AppColors.warning;
              indicatorIcon = Icons.cloud_upload_rounded;
              tooltip = LocalizationHelper.syncPreparing;
            } else if (!syncService.isOnline) {
              indicatorColor = AppColors.error;
              indicatorIcon = Icons.cloud_off_rounded;
              tooltip = LocalizationHelper.noInternet;
            } else {
              indicatorColor = AppColors.success;
              indicatorIcon = Icons.cloud_done_rounded;
              tooltip = LocalizationHelper.syncCompleted;
            }
        }

        final lastSync = syncService.lastSuccessfulSync;
        String subtitle = '';
        if (lastSync != null) {
          final diff = DateTime.now().difference(lastSync);
          if (diff.inMinutes < 1) {
            subtitle = LocalizationHelper.syncJustNow;
          } else if (diff.inMinutes < 60) {
            subtitle = '${diff.inMinutes} ${LocalizationHelper.dashboardMinutesAgo}';
          } else if (diff.inHours < 24) {
            subtitle = '${diff.inHours} ${LocalizationHelper.dashboardHoursAgo}';
          } else {
            subtitle = '${diff.inDays} ${LocalizationHelper.dashboardDaysAgo}';
          }
        } else if (syncService.pendingSyncCount > 0) {
          subtitle = LocalizationHelper.syncPendingItems(syncService.pendingSyncCount);
        } else if (!syncService.isOnline) {
          subtitle = LocalizationHelper.noInternet;
        }

        final child = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                indicatorIcon,
                key: ValueKey(status),
                color: indicatorColor,
                size: showAsFloating ? 20 : 16,
              ),
            ),
            if (!showAsFloating && subtitle.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.textDarkTertiary : AppColors.textLightTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        );

        if (showAsFloating) {
          return Positioned(
            bottom: 100,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: indicatorColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(indicatorIcon, color: indicatorColor, size: 18),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tooltip,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? AppColors.textDarkTertiary : AppColors.textLightTertiary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return IconButton(
          onPressed: onTap,
          icon: child,
          tooltip: '$tooltip${subtitle.isNotEmpty ? '\n$subtitle' : ''}',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        );
      },
    );
  }
}