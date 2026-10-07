import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_providers.dart';
import '../../widgets/vocation_logo.dart';
import '../profile/sign_out.dart';

/// Asks whether the person is looking for work or hiring. Also used to switch.
class RoleChoiceScreen extends ConsumerWidget {
  const RoleChoiceScreen({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref, UserRole role) async {
    await ref.read(roleProvider.notifier).choose(role);
    if (context.mounted) context.go(homeFor(role));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(roleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const VocationLogo(size: 28),
        actions: [TextButton(onPressed: () => confirmAndSignOut(context, ref), child: const Text('Sign out'))],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(current == null ? 'How will you use Vocation SL?' : 'Switch how you use Vocation SL',
                    style: context.text.headlineMedium),
                const SizedBox(height: 8),
                Text('You can switch at any time from your settings.', style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, c) {
                  final cards = [
                    _RoleCard(
                      icon: Icons.search_rounded,
                      title: 'Find a job',
                      body: 'Search jobs across Sierra Leone, apply with your CV and track every application.',
                      selected: current == UserRole.seeker,
                      onTap: () => _pick(context, ref, UserRole.seeker),
                    ),
                    _RoleCard(
                      icon: Icons.business_center_outlined,
                      title: 'Hire talent',
                      body: 'Post jobs for your company, review candidates and manage your hiring pipeline.',
                      selected: current == UserRole.employer,
                      onTap: () => _pick(context, ref, UserRole.employer),
                    ),
                  ];
                  if (c.maxWidth < 560) return Column(children: [cards[0], const SizedBox(height: 12), cards[1]]);
                  return IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ]),
                  );
                }),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.title, required this.body, required this.onTap, this.selected = false});
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '$title. $body',
        excludeSemantics: true,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            side: BorderSide(color: selected ? context.colors.primary : context.palette.border, width: selected ? 2 : 1),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: context.palette.accentTint, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: context.colors.primary),
                ),
                const SizedBox(height: 16),
                Text(title, style: context.text.titleLarge),
                const SizedBox(height: 6),
                Text(body, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                const SizedBox(height: 16),
                Text(selected ? 'Current' : 'Continue →', style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
              ]),
            ),
          ),
        ),
      );
}

/// Switches the signed-in user to the other side of the app.
Future<void> switchRole(BuildContext context, WidgetRef ref, UserRole role) async {
  await ref.read(roleProvider.notifier).choose(role);
  if (context.mounted) context.go(homeFor(role));
}
