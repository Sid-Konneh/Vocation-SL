import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';
import '../features/profile/sign_out.dart';
import '../models/models.dart';
import '../providers/session_providers.dart';
import '../widgets/skeletons.dart';
import '../widgets/states.dart';
import '../widgets/vocation_logo.dart';
import 'admin_providers.dart';

class AdminSection {
  const AdminSection(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const adminSections = [
  AdminSection('/admin/overview', 'Overview', Icons.space_dashboard_outlined),
  AdminSection('/admin/insights', 'Insights', Icons.insights_outlined),
  AdminSection('/admin/jobs', 'Job moderation', Icons.fact_check_outlined),
  AdminSection('/admin/employers', 'Employer verification', Icons.verified_user_outlined),
  AdminSection('/admin/users', 'Users', Icons.people_outline_rounded),
  AdminSection('/admin/applications', 'Applications', Icons.assignment_outlined),
  AdminSection('/admin/reports', 'Reports', Icons.flag_outlined),
  AdminSection('/admin/invoices', 'Invoices', Icons.receipt_long_outlined),
  AdminSection('/admin/content', 'Content', Icons.campaign_outlined),
  AdminSection('/admin/settings', 'Platform settings', Icons.tune_rounded),
  AdminSection('/admin/team', 'Admin team', Icons.admin_panel_settings_outlined),
  AdminSection('/admin/activity', 'Activity log', Icons.history_rounded),
];

/// Admin frame: checks the user is an admin, then shows the navigation.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(adminRoleProvider);
    if (role.isLoading && !role.hasValue) return const ShellSkeleton();
    if (role.value == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Admins only',
          message: 'Your account doesn\'t have access to the admin dashboard.',
          action: 'Back to the app',
          onAction: () => context.go(homeFor(ref.read(roleProvider))),
        ),
      );
    }
    final myRole = role.value!;
    final pending = ref.watch(adminStatsProvider).value;
    int? badgeFor(String path) => switch (path) {
          '/admin/jobs' => pending?.jobsPending,
          '/admin/employers' => pending?.companiesPending,
          '/admin/reports' => pending?.reportsOpen,
          _ => null,
        };

    final current = adminSections.where((s) => location.startsWith(s.path)).firstOrNull ?? adminSections.first;

    Widget nav({required bool drawer}) => SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 4), child: Align(alignment: Alignment.centerLeft, child: VocationLogo(size: 30))),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Text('Admin · ${myRole.label}', style: context.text.labelLarge?.copyWith(color: context.palette.muted)),
              ),
              Expanded(
                child: ListView(padding: EdgeInsets.zero, children: [
                  for (final s in adminSections)
                    _NavRow(
                      icon: s.icon,
                      label: s.label,
                      badge: badgeFor(s.path),
                      selected: s == current,
                      onTap: () {
                        if (drawer) Navigator.pop(context);
                        context.go(s.path);
                      },
                    ),
                ]),
              ),
              const Divider(),
              const SizedBox(height: 8),
              _NavRow(
                icon: Icons.arrow_back_rounded,
                label: 'Back to the app',
                onTap: () => context.go(homeFor(ref.read(roleProvider))),
              ),
              _NavRow(icon: Icons.logout_rounded, label: 'Sign out', onTap: () => confirmAndSignOut(context, ref)),
            ]),
          ),
        );

    if (context.isWide) {
      return Scaffold(
        body: Row(children: [
          SizedBox(width: 264, child: nav(drawer: false)),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(current.label)),
      drawer: Drawer(child: nav(drawer: true)),
      body: child,
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap, this.selected = false, this.badge});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int? badge;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Semantics(
          button: true,
          selected: selected,
          label: badge != null && badge! > 0 ? '$label, $badge waiting' : label,
          excludeSemantics: true,
          child: Material(
            color: selected ? context.colors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  Icon(icon, size: 22, color: selected ? context.colors.primary : context.palette.muted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          color: selected ? context.colors.onPrimaryContainer : context.colors.onSurface,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        )),
                  ),
                  if (badge != null && badge! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(100)),
                      child: Text('$badge', style: context.text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Shows loading / error / data for an admin list, with retry.
class AdminAsync<T> extends StatelessWidget {
  const AdminAsync({super.key, required this.value, required this.onRetry, required this.builder, this.skeleton});
  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  /// Loading placeholder; defaults to a shimmering list.
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) => value.when(
        skipLoadingOnRefresh: true,
        loading: () => skeleton ?? const Skeleton(child: Column(children: [ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true)])),
        error: (e, _) => ErrorState(error: e, onRetry: onRetry),
        data: builder,
      );
}

/// True when the signed-in admin's role is at least [needed].
bool adminCan(WidgetRef ref, AdminRole needed) => ref.watch(adminRoleProvider).value?.can(needed) ?? false;
