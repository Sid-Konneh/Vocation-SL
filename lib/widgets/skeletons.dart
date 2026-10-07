import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_theme.dart';

/// Shimmering placeholder shapes that mirror the real layouts, so the page
/// structure is visible while data loads.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final content = Semantics(label: 'Loading', liveRegion: true, child: ExcludeSemantics(child: child));
    if (reduceMotion) return content;
    return Shimmer.fromColors(
      baseColor: dark ? const Color(0xFF222823) : const Color(0xFFECEFE9),
      highlightColor: dark ? const Color(0xFF2E352F) : const Color(0xFFF8FAF6),
      period: const Duration(milliseconds: 1300),
      child: content,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF222823) : const Color(0xFFECEFE9),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class JobCardSkeleton extends StatelessWidget {
  const JobCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: context.palette.border),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SkeletonBox(width: 48, height: 48, radius: 14),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SkeletonBox(width: 190, height: 16),
                SizedBox(height: 8),
                SkeletonBox(width: 120, height: 12),
              ]),
            ),
          ]),
          SizedBox(height: 14),
          Row(children: [
            SkeletonBox(width: 84, height: 24, radius: 100),
            SizedBox(width: 6),
            SkeletonBox(width: 76, height: 24, radius: 100),
            SizedBox(width: 6),
            SkeletonBox(width: 64, height: 24, radius: 100),
          ]),
          SizedBox(height: 14),
          SkeletonBox(width: 160, height: 14),
          SizedBox(height: 12),
          SkeletonBox(width: 200, height: 10),
        ]),
      );
}

/// A column of job card skeletons; use inside scroll views.
class JobListSkeleton extends StatelessWidget {
  const JobListSkeleton({super.key, this.count = 4, this.padding = EdgeInsets.zero});
  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Padding(
          padding: padding,
          child: Column(children: [
            for (var i = 0; i < count; i++) ...[const JobCardSkeleton(), const SizedBox(height: 12)],
          ]),
        ),
      );
}

class JobDetailSkeleton extends StatelessWidget {
  const JobDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Skeleton(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.gutter),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 72, height: 72, radius: 20),
            SizedBox(height: 20),
            SkeletonBox(width: 260, height: 26),
            SizedBox(height: 10),
            SkeletonBox(width: 180, height: 16),
            SizedBox(height: 20),
            Row(children: [
              SkeletonBox(width: 90, height: 28, radius: 100),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 28, radius: 100),
              SizedBox(width: 8),
              SkeletonBox(width: 70, height: 28, radius: 100),
            ]),
            SizedBox(height: 28),
            SkeletonBox(height: 84, radius: 16),
            SizedBox(height: 28),
            SkeletonBox(width: 140, height: 20),
            SizedBox(height: 14),
            SkeletonBox(height: 12),
            SizedBox(height: 8),
            SkeletonBox(height: 12),
            SizedBox(height: 8),
            SkeletonBox(width: 240, height: 12),
            SizedBox(height: 28),
            SkeletonBox(width: 180, height: 20),
            SizedBox(height: 14),
            SkeletonBox(height: 12),
            SizedBox(height: 8),
            SkeletonBox(width: 280, height: 12),
          ]),
        ),
      );
}

class ListTileSkeleton extends StatelessWidget {
  const ListTileSkeleton({super.key, this.leadingCircle = false, this.trailing = false});
  final bool leadingCircle;
  final bool trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkeletonBox(width: 44, height: 44, radius: leadingCircle ? 22 : 12),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: 200, height: 14),
              SizedBox(height: 8),
              SkeletonBox(height: 12),
              SizedBox(height: 6),
              SkeletonBox(width: 90, height: 10),
            ]),
          ),
          if (trailing) ...[const SizedBox(width: 12), const SkeletonBox(width: 70, height: 24, radius: 100)],
        ]),
      );
}

class NotificationListSkeleton extends StatelessWidget {
  const NotificationListSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Column(children: [for (var i = 0; i < 7; i++) const ListTileSkeleton(leadingCircle: true)]),
        ),
      );
}

class ApplicationListSkeleton extends StatelessWidget {
  const ApplicationListSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(children: [
            const Row(children: [
              Expanded(child: SkeletonBox(height: 76, radius: 16)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 76, radius: 16)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 76, radius: 16)),
            ]),
            const SizedBox(height: 20),
            for (var i = 0; i < 4; i++) ...[const SkeletonBox(height: 128, radius: 16), const SizedBox(height: 12)],
          ]),
        ),
      );
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Skeleton(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.gutter),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SkeletonBox(width: 88, height: 88, radius: 44),
              SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SkeletonBox(width: 170, height: 20),
                  SizedBox(height: 10),
                  SkeletonBox(width: 220, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 100, height: 12),
                ]),
              ),
            ]),
            SizedBox(height: 24),
            SkeletonBox(height: 96, radius: 16),
            SizedBox(height: 24),
            SkeletonBox(width: 120, height: 18),
            SizedBox(height: 12),
            SkeletonBox(height: 12),
            SizedBox(height: 8),
            SkeletonBox(width: 260, height: 12),
            SizedBox(height: 24),
            SkeletonBox(width: 140, height: 18),
            SizedBox(height: 12),
            ListTileSkeleton(),
            ListTileSkeleton(),
          ]),
        ),
      );
}
