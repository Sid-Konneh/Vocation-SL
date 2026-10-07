import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../widgets/job_card.dart';

/// Job cards as a sliver: one column on phones, two on tablets/desktop.
class JobListSliver extends StatelessWidget {
  const JobListSliver({super.key, required this.jobs, this.showDescription = false});
  final List<Job> jobs;
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 2 : (width >= 700 ? 2 : 1);
    if (columns == 1) {
      return SliverList.separated(
        itemCount: jobs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _Appear(index: i, child: JobCard(job: jobs[i], showDescription: showDescription)),
      );
    }
    final rows = (jobs.length / columns).ceil();
    return SliverList.separated(
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, r) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var c = 0; c < columns; c++) ...[
            if (c > 0) const SizedBox(width: 12),
            Expanded(
              child: r * columns + c < jobs.length
                  ? JobCard(job: jobs[r * columns + c], showDescription: showDescription)
                  : const SizedBox(),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Subtle fade/slide-in for the first items of a list.
class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (index > 6 || MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 40),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: c)),
      child: child,
    );
  }
}

EdgeInsets pagePadding(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final side = w > AppSpacing.maxContentWidth ? (w - AppSpacing.maxContentWidth) / 2 : AppSpacing.gutter;
  return EdgeInsets.symmetric(horizontal: context.isWide ? side.clamp(24.0, double.infinity) : side);
}
