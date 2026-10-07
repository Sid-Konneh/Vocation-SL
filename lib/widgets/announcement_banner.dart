import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/admin_providers.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';

/// Maintenance notice and live announcements for [audience]. Each
/// announcement can be dismissed for the rest of the session.
class AnnouncementBanner extends ConsumerStatefulWidget {
  const AnnouncementBanner({super.key, required this.audience, this.padding = EdgeInsets.zero});
  final AnnouncementAudience audience;
  final EdgeInsets padding;

  @override
  ConsumerState<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends ConsumerState<AnnouncementBanner> {
  static final _dismissed = <String>{};

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(platformSettingsProvider).value;
    final list = (ref.watch(announcementsProvider).value ?? const <Announcement>[])
        .where((a) => (a.audience == AnnouncementAudience.all || a.audience == widget.audience) && !_dismissed.contains(a.id))
        .toList();
    final items = <Widget>[
      if (settings?.maintenanceEnabled ?? false)
        _Banner(
          color: AppColors.warning,
          icon: Icons.construction_rounded,
          title: 'Maintenance',
          body: settings!.maintenanceMessage.isEmpty ? 'Some features may be unavailable for a short time.' : settings.maintenanceMessage,
        ),
      for (final a in list)
        _Banner(
          color: switch (a.level) { AnnouncementLevel.warning => AppColors.warning, AnnouncementLevel.success => AppColors.success, _ => AppColors.info },
          icon: switch (a.level) { AnnouncementLevel.warning => Icons.warning_amber_rounded, AnnouncementLevel.success => Icons.celebration_outlined, _ => Icons.campaign_outlined },
          title: a.title,
          body: a.body,
          onDismiss: () => setState(() => _dismissed.add(a.id)),
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(padding: widget.padding, child: Column(children: items));
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.title, required this.body, this.onDismiss});
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(body, style: context.text.bodyMedium)),
              ]),
            ),
            if (onDismiss != null) IconButton(tooltip: 'Dismiss', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onDismiss),
          ]),
        ),
      );
}
