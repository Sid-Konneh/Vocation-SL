import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/hiring_providers.dart';

/// How long ago the person applied, and how quickly this employer usually
/// replies (from their real reply times over the last 6 months).
class ApplicationTracker extends ConsumerWidget {
  const ApplicationTracker({super.key, required this.application});
  final JobApplication application;

  static String _ago(Duration d) {
    if (d.inHours < 24) return 'today';
    final days = d.inDays;
    if (days < 14) return '$days day${days == 1 ? '' : 's'} ago';
    return '${(days / 7).floor()} weeks ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = application;
    final companyId = a.job?.companyId;
    if (a.pendingSync || companyId == null) return const SizedBox.shrink();
    final speed = ref.watch(replySpeedProvider(companyId)).value;
    final waited = DateTime.now().difference(a.submittedAt);
    final waiting = a.status == ApplicationStatus.applied;
    final muted = context.palette.muted;

    String? hint;
    if (speed != null && speed.hasEnoughData) {
      final typicalDays = (speed.medianHours! / 24).ceil();
      hint = 'This employer usually replies ${speed.typical} '
          '(${speed.replied} of ${speed.applications} applicants heard back in the last 6 months).';
      if (waiting && waited.inDays > typicalDays * 2 && waited.inDays >= 7) {
        hint = '$hint It\'s been longer than usual. Keep applying elsewhere; you can still hear back.';
      }
    } else if (speed != null) {
      hint = 'Not enough replies yet to say how quickly this employer usually responds.';
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.hourglass_bottom_rounded, color: context.colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              waiting ? 'You applied ${_ago(waited)}. Waiting for the employer.' : 'You applied ${_ago(waited)}.',
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: context.text.bodyMedium?.copyWith(color: muted)),
            ],
          ]),
        ),
      ]),
    );
  }
}
