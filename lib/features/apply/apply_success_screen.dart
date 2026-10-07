import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/user_data_providers.dart';

class ApplySuccessScreen extends ConsumerWidget {
  const ApplySuccessScreen({super.key, required this.applicationId});
  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(applicationByIdProvider(applicationId));
    final pending = app?.pendingSync ?? false;
    final reduce = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduce ? 1 : 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.elasticOut,
                  builder: (_, t, child) => Transform.scale(scale: t, child: child),
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pending ? AppColors.warning.withValues(alpha: 0.12) : context.palette.accentTint,
                    ),
                    child: Icon(
                      pending ? Icons.schedule_send_rounded : Icons.check_rounded,
                      size: 60,
                      color: pending ? AppColors.warning : context.colors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Semantics(
                  liveRegion: true,
                  header: true,
                  child: Text(pending ? 'Application saved' : 'Application sent!', textAlign: TextAlign.center, style: context.text.headlineMedium),
                ),
                const SizedBox(height: 10),
                Text(
                  pending
                      ? 'You\'re offline. We\'ll send your application for ${app?.job?.title ?? 'this job'} automatically when you reconnect.'
                      : 'Your application for ${app?.job?.title ?? 'this job'} at ${app?.job?.companyName ?? 'the employer'} has been submitted.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyLarge?.copyWith(color: context.palette.muted),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(border: Border.all(color: context.palette.border), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('What happens next', style: context.text.titleMedium),
                    const SizedBox(height: 12),
                    const _Next(icon: Icons.visibility_outlined, text: 'We\'ll notify you when the employer views your application.'),
                    const _Next(icon: Icons.star_outline_rounded, text: 'If you\'re shortlisted, you may be asked for an assessment or interview.'),
                    const _Next(icon: Icons.track_changes_rounded, text: 'Follow every step in Applications.'),
                  ]),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      context.go('/applications');
                      if (app != null) context.push('/application/${app.id}');
                    },
                    icon: const Icon(Icons.track_changes_rounded),
                    label: const Text('Track application'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: () => context.go('/jobs'), child: const Text('Find more jobs')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Next extends StatelessWidget {
  const _Next({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ]),
      );
}
