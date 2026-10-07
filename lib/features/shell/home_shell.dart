import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/vocation_logo.dart';
import '../profile/sign_out.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Dest('Jobs', Icons.search_rounded, Icons.manage_search_rounded),
  _Dest('Saved', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
  _Dest('Applied', Icons.work_outline_rounded, Icons.work_rounded),
  _Dest('Alerts', Icons.notifications_none_rounded, Icons.notifications_rounded),
  _Dest('Profile', Icons.person_outline_rounded, Icons.person_rounded),
];

/// Bottom navigation on phones, a navigation rail on tablets and desktop.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final activeApps = ref.watch(applicationsProvider).value?.data.where((a) => a.status.isActive && a.employerMessage != null).length ?? 0;

    Widget icon(int i, bool selected) {
      final d = _destinations[i];
      final base = Icon(selected ? d.selectedIcon : d.icon);
      final count = i == 3 ? unread : 0;
      if (count == 0) return base;
      return Badge(label: Text(count > 99 ? '99+' : '$count'), backgroundColor: AppColors.danger, child: base);
    }

    String semantic(int i) {
      final d = _destinations[i];
      if (i == 3 && unread > 0) return '${d.label}, $unread unread';
      if (i == 2) return activeApps > 0 ? 'Applications, $activeApps with employer messages' : 'Applications';
      return d.label;
    }

    if (context.isWide) {
      return Scaffold(
        body: Row(children: [
          _Sidebar(
            selected: shell.currentIndex,
            onSelect: _go,
            iconFor: icon,
            semanticFor: semantic,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ]),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.palette.border))),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (var i = 0; i < _destinations.length; i++)
              NavigationDestination(
                icon: icon(i, false),
                selectedIcon: icon(i, true),
                label: _destinations[i].label,
                tooltip: semantic(i),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desktop/tablet sidebar: icon and label side by side, About and Sign out at the bottom.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.selected, required this.onSelect, required this.iconFor, required this.semanticFor});
  final int selected;
  final void Function(int) onSelect;
  final Widget Function(int index, bool selected) iconFor;
  final String Function(int index) semanticFor;

  static const _sidebarLabels = ['Jobs', 'Saved', 'Applications', 'Alerts', 'Profile'];

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        width: 248,
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 24),
                child: Align(alignment: Alignment.centerLeft, child: VocationLogo(size: 34)),
              ),
              for (var i = 0; i < _sidebarLabels.length; i++)
                _SidebarItem(
                  icon: iconFor(i, i == selected),
                  label: _sidebarLabels[i],
                  semantics: semanticFor(i),
                  selected: i == selected,
                  onTap: () => onSelect(i),
                ),
              const Spacer(),
              const Divider(),
              const SizedBox(height: 8),
              _SidebarItem(
                icon: const Icon(Icons.info_outline_rounded),
                label: 'About',
                semantics: 'About Vocation SL',
                onTap: () => context.push('/about'),
              ),
              _SidebarItem(
                icon: const Icon(Icons.logout_rounded),
                label: 'Sign out',
                semantics: 'Sign out',
                onTap: () => confirmAndSignOut(context, ref),
              ),
            ]),
          ),
        ),
      );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.icon, required this.label, required this.semantics, required this.onTap, this.selected = false});
  final Widget icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.colors.onPrimaryContainer : context.colors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: semantics,
        excludeSemantics: true,
        child: Material(
          color: selected ? context.colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                IconTheme(
                  data: IconThemeData(color: selected ? context.colors.primary : context.palette.muted, size: 24),
                  child: icon,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
