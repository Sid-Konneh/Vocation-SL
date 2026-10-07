import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../jobs/job_list_sliver.dart';

IconData notificationIcon(NotificationType t) => switch (t) {
      NotificationType.newMatch => Icons.auto_awesome_rounded,
      NotificationType.savedSearch => Icons.manage_search_rounded,
      NotificationType.submitted => Icons.send_rounded,
      NotificationType.viewed => Icons.visibility_rounded,
      NotificationType.shortlisted => Icons.star_rounded,
      NotificationType.interview => Icons.event_rounded,
      NotificationType.statusChange => Icons.sync_alt_rounded,
      NotificationType.message => Icons.mail_rounded,
      NotificationType.deadline => Icons.timer_rounded,
    };

Color notificationColor(NotificationType t) => switch (t) {
      NotificationType.newMatch || NotificationType.savedSearch => AppColors.green,
      NotificationType.submitted || NotificationType.viewed => AppColors.info,
      NotificationType.shortlisted => AppColors.purple,
      NotificationType.interview => const Color(0xFFD9570F),
      NotificationType.statusChange => const Color(0xFF4F6BD8),
      NotificationType.message => const Color(0xFF16808F),
      NotificationType.deadline => AppColors.warning,
    };

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;

  void _open(AppNotification n) {
    if (!n.read) ref.read(notificationsProvider.notifier).markRead([n.id]);
    if (n.applicationId != null) {
      context.push('/application/${n.applicationId}');
    } else if (n.jobId != null) {
      context.push('/job/${n.jobId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final pad = pagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          if (unread > 0)
            TextButton(onPressed: () => ref.read(notificationsProvider.notifier).markAllRead(), child: const Text('Mark all read')),
          IconButton(
            tooltip: 'Notification settings',
            onPressed: () => context.push('/settings/notifications'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: async.when(
        loading: () => const SingleChildScrollView(child: NotificationListSkeleton()),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
        data: (loaded) {
          final list = _unreadOnly ? loaded.data.where((n) => !n.read).toList() : loaded.data;
          final groups = <String, List<AppNotification>>{};
          final now = DateTime.now();
          for (final n in list) {
            final d = now.difference(n.createdAt).inDays;
            final key = n.createdAt.day == now.day && d == 0 ? 'Today' : (d < 7 ? 'This week' : 'Earlier');
            groups.putIfAbsent(key, () => []).add(n);
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              SliverPadding(
                padding: pad.copyWith(top: 8, bottom: 8),
                sliver: SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (loaded.isOfflineCopy)
                      CacheNotice(syncedAt: loaded.syncedAt, onRetry: () => ref.read(notificationsProvider.notifier).refresh()),
                    Row(children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: !_unreadOnly,
                        onSelected: (_) => setState(() => _unreadOnly = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('Unread ($unread)'),
                        selected: _unreadOnly,
                        onSelected: (_) => setState(() => _unreadOnly = true),
                      ),
                    ]),
                  ]),
                ),
              ),
              if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: _unreadOnly ? 'You\'re all caught up' : 'No alerts yet',
                    message: _unreadOnly
                        ? 'No unread notifications.'
                        : 'We\'ll let you know about new matching jobs, application updates and employer messages.',
                    action: _unreadOnly ? null : 'Create a job alert',
                    onAction: () => context.push('/search'),
                  ),
                )
              else
                for (final entry in groups.entries) ...[
                  SliverPadding(
                    padding: pad.copyWith(top: 16, bottom: 4),
                    sliver: SliverToBoxAdapter(
                      child: Text(entry.key, style: context.text.labelLarge?.copyWith(color: context.palette.muted)),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: entry.value.length,
                    itemBuilder: (_, i) {
                      final n = entry.value[i];
                      return Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: AppColors.danger,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          ref.read(notificationsProvider.notifier).delete(n.id);
                          showSnack(context, 'Notification deleted');
                        },
                        child: _NotificationTile(n: n, onTap: () => _open(n), padding: pad),
                      );
                    },
                  ),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap, required this.padding});
  final AppNotification n;
  final VoidCallback onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final color = notificationColor(n.type);
    return Semantics(
      label: '${n.read ? '' : 'Unread. '}${n.title}. ${n.body}. ${Fmt.ago(n.createdAt)}',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: n.read ? null : context.palette.accentTint.withValues(alpha: 0.6),
          padding: padding.copyWith(top: 14, bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(notificationIcon(n.type), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title, style: context.text.titleSmall?.copyWith(fontWeight: n.read ? FontWeight.w600 : FontWeight.w800)),
                const SizedBox(height: 2),
                Text(n.body, style: context.text.bodyMedium?.copyWith(color: context.palette.muted), maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('${n.type.label} · ${Fmt.ago(n.createdAt)}', style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
              ]),
            ),
            if (!n.read)
              Container(
                margin: const EdgeInsets.only(top: 6, left: 8),
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }
}
