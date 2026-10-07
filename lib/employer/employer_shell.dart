import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../admin/admin_providers.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/role_choice_screen.dart';
import '../features/profile/sign_out.dart';
import '../models/models.dart';
import '../widgets/states.dart';
import '../widgets/vocation_logo.dart';
import 'features/company/company_screens.dart';
import 'providers.dart';

class _Item {
  const _Item(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

// Branch order must match the router.
const _items = [
  _Item('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Item('Insights', Icons.insights_outlined, Icons.insights_rounded),
  _Item('My jobs', Icons.work_outline_rounded, Icons.work_rounded),
  _Item('Candidates', Icons.people_outline_rounded, Icons.people_rounded),
  _Item('Company profile', Icons.business_outlined, Icons.business_rounded),
];

/// Phone bottom bar shows these branches, plus "More" for the rest.
const _phoneBranches = [0, 2, 3];

/// Gate + navigation: shows company setup until the user has a company.
class EmployerShell extends ConsumerWidget {
  const EmployerShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyAsync = ref.watch(companyProvider);
    if (!companyAsync.hasValue) {
      if (companyAsync.hasError) {
        return Scaffold(body: ErrorState(error: companyAsync.error!, onRetry: () => ref.invalidate(companyProvider)));
      }
      return const Scaffold(body: Center(child: VocationMark(size: 64)));
    }
    if (companyAsync.value!.data == null) return const CompanySetupScreen();

    final toReview = ref.watch(candidatesProvider).value?.data.where((a) => a.status == ApplicationStatus.applied).length ?? 0;
    Widget icon(int i, bool selected) {
      final base = Icon(selected ? _items[i].selectedIcon : _items[i].icon);
      if (i != 3 || toReview == 0) return base;
      return Badge(label: Text(toReview > 99 ? '99+' : '$toReview'), backgroundColor: AppColors.danger, child: base);
    }

    if (context.isWide) {
      return Scaffold(
        body: Row(children: [
          SizedBox(
            width: 256,
            child: SafeArea(
              right: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Align(alignment: Alignment.centerLeft, child: VocationLogo(size: 32)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    child: Text('for Employers', style: context.text.labelLarge?.copyWith(color: context.palette.muted)),
                  ),
                  for (var i = 0; i < _items.length; i++)
                    _NavRow(
                      icon: icon(i, i == shell.currentIndex),
                      label: _items[i].label,
                      semantics: i == 3 && toReview > 0 ? 'Candidates, $toReview to review' : _items[i].label,
                      selected: i == shell.currentIndex,
                      onTap: () => _go(i),
                    ),
                  const Spacer(),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (ref.watch(adminRoleProvider).value != null)
                    _NavRow(icon: const Icon(Icons.admin_panel_settings_outlined), label: 'Admin dashboard', semantics: 'Admin dashboard', onTap: () => context.go('/admin')),
                  _NavRow(icon: const Icon(Icons.swap_horiz_rounded), label: 'Switch to job seeker', semantics: 'Switch to job seeker', onTap: () => switchRole(context, ref, UserRole.seeker)),
                  _NavRow(icon: const Icon(Icons.info_outline_rounded), label: 'About', semantics: 'About Vocation SL', onTap: () => context.push('/about')),
                  _NavRow(icon: const Icon(Icons.logout_rounded), label: 'Sign out', semantics: 'Sign out', onTap: () => confirmAndSignOut(context, ref)),
                ]),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ]),
      );
    }

    final phoneIndex = _phoneBranches.indexOf(shell.currentIndex);
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.palette.border))),
        child: NavigationBar(
          selectedIndex: phoneIndex < 0 ? _phoneBranches.length : phoneIndex,
          onDestinationSelected: (i) {
            if (i < _phoneBranches.length) {
              _go(_phoneBranches[i]);
            } else {
              _showMore(context, ref);
            }
          },
          destinations: [
            for (final b in _phoneBranches)
              NavigationDestination(icon: icon(b, false), selectedIcon: icon(b, true), label: b == 2 ? 'Jobs' : _items[b].label),
            const NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }

  void _showMore(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final i in [1, 4])
              ListTile(
                leading: Icon(_items[i].icon),
                title: Text(_items[i].label),
                onTap: () {
                  Navigator.pop(sheet);
                  _go(i);
                },
              ),
            if (ref.read(adminRoleProvider).value != null)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Admin dashboard'),
                onTap: () {
                  Navigator.pop(sheet);
                  context.go('/admin');
                },
              ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Switch to job seeker'),
              onTap: () {
                Navigator.pop(sheet);
                switchRole(context, ref, UserRole.seeker);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/about');
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Change password'),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/settings/password');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: AppColors.danger),
              title: const Text('Delete account', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/account/delete');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.pop(sheet);
                confirmAndSignOut(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.semantics, required this.onTap, this.selected = false});
  final Widget icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
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
                  IconTheme(data: IconThemeData(color: selected ? context.colors.primary : context.palette.muted, size: 24), child: icon),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          color: selected ? context.colors.onPrimaryContainer : context.colors.onSurface,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        )),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
