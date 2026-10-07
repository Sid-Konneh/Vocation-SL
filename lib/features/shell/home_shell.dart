import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/vocation_logo.dart';

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
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: VocationMark(size: 40)),
            destinations: [
              for (var i = 0; i < _destinations.length; i++)
                NavigationRailDestination(
                  icon: Semantics(label: semantic(i), child: icon(i, false)),
                  selectedIcon: icon(i, true),
                  label: Text(_destinations[i].label),
                ),
            ],
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
