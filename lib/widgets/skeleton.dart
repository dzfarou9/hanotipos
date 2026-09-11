// lib/widgets/skeleton.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';

/// عظم واحد (bone) بنبض خفيف — لبنة بناء حالات التحميل الهيكلية.
///
/// النبض opacity-only (بدون layout) فيعمل على 60fps حتى على أجهزة ضعيفة.
class AppSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const AppSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = DesignTokens.radiusXs,
  });

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesignTokens.animSlow,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : AppColors.grey200.withValues(alpha: 0.8);
    final peakColor = isDark
        ? Colors.white.withValues(alpha: 0.11)
        : AppColors.grey300;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(baseColor, peakColor, t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// حالة تحميل هيكلية تحاكي شكل الشاشات القائمةية:
/// (اختياري) بطاقة ملخص + حقل بحث + صفوف قائمة بأفاتار وسطرين.
///
/// بديل موحّد لـ CircularProgressIndicator في مسارات التحميل الأولي.
class SkeletonLoadingView extends StatelessWidget {
  final bool summaryCard;
  final int rows;

  const SkeletonLoadingView({
    super.key,
    this.summaryCard = true,
    this.rows = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.pageMargin,
        DesignTokens.space8,
        DesignTokens.pageMargin,
        DesignTokens.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summaryCard) ...[
            Container(
              height: 132,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : AppColors.primary.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
              padding: const EdgeInsets.all(DesignTokens.space20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 120, height: 14),
                  const SizedBox(height: DesignTokens.space16),
                  Row(
                    children: [
                      Expanded(
                        child: AppSkeleton(height: 56, radius: DesignTokens.radiusSm),
                      ),
                      const SizedBox(width: DesignTokens.space12),
                      Expanded(
                        child: AppSkeleton(height: 56, radius: DesignTokens.radiusSm),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.space16),
          ],
          AppSkeleton(height: 48, radius: DesignTokens.radiusMd),
          const SizedBox(height: DesignTokens.space16),
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: rows,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.space12),
                child: Row(
                  children: [
                    AppSkeleton(
                      width: 44,
                      height: 44,
                      radius: DesignTokens.radiusSm,
                    ),
                    const SizedBox(width: DesignTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.55,
                            alignment: AlignmentDirectional.centerStart,
                            child: AppSkeleton(height: 12),
                          ),
                          const SizedBox(height: DesignTokens.space8),
                          FractionallySizedBox(
                            widthFactor: 0.35,
                            alignment: AlignmentDirectional.centerStart,
                            child: AppSkeleton(height: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space12),
                    AppSkeleton(width: 56, height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
