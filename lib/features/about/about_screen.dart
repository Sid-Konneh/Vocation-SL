import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/vocation_logo.dart';

/// About Vocation SL: what the platform does, how data is handled, and how to get help.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  Future<void> _email(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: AppConfig.supportEmail, query: 'subject=Vocation SL support');
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {}
    if (!opened && context.mounted) await _copy(context);
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: AppConfig.supportEmail));
    if (context.mounted) showSnack(context, 'Email address copied');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = isDemoBackend(ref.watch(backendProvider));
    final muted = context.palette.muted;

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: context.text.titleLarge)),
            const SizedBox(height: 12),
            ...children,
          ]),
        );

    Widget body(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(text, style: context.text.bodyLarge),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ResponsiveCenter(
        maxWidth: AppSpacing.maxReadingWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 48),
          children: [
            const Align(alignment: Alignment.centerLeft, child: VocationLogo(size: 44)),
            const SizedBox(height: 24),
            Text('About Vocation SL', style: context.text.headlineMedium),
            const SizedBox(height: 12),
            Text(
              'Vocation SL is a job discovery and application platform built for Sierra Leone. '
              'It brings job openings from across the country into one place and makes it simple to apply, '
              'follow your applications and hear back from employers, all from your phone or computer.',
              style: context.text.bodyLarge?.copyWith(fontSize: 17),
            ),
            section('Our mission', [
              body('Finding work in Sierra Leone often depends on who you know, which notice board you pass, or which '
                  'WhatsApp group you are in. Vocation SL exists to make opportunities easier to find and fairer to reach, '
                  'so that skilled people in Freetown, Bo, Kenema, Makeni, Port Loko and every district can find the right '
                  'role and employers can find the right people.'),
            ]),
            section('What you can do', [
              const BulletList([
                'Search jobs by title, skill, company or location, and filter by industry, job type, experience, salary, remote work and date posted.',
                'Save jobs and searches, and get alerts when new matching roles are posted.',
                'Apply in a few steps with your CV, a cover letter and a note to the employer.',
                'Track every application, from submitted to viewed, shortlisted, interview and offer.',
                'Build a profile that shows employers your experience, skills, languages and certifications.',
                'Keep browsing when your connection drops; changes sync when you are back online.',
              ], icon: Icons.check_circle_outline_rounded),
            ]),
            section('For employers', [
              body('Organisations that want to list vacancies on Vocation SL can contact us at the email address below.'),
            ]),
            section('Your data', [
              body('Your profile, CV and applications are tied to your account and protected by access rules: other users '
                  'cannot see them. Your documents are shared with an employer only when you apply to that employer\'s job.'),
              body('You can update your profile at any time, and delete your account and data from Settings → Delete account.'),
            ]),
            section(demo ? 'Demo mode' : 'Genuine listings', [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppSpacing.radius)),
                child: Text(
                  demo
                      ? 'You are using demo mode. All employers, jobs and the demo profile are fictional examples, and nothing you do leaves this device.'
                      : 'Every company and every job on Vocation SL is reviewed by our team before it goes live. A genuine employer will never ask you for money to apply. If anyone does, report the job.',
                  style: context.text.bodyMedium,
                ),
              ),
            ]),
            section('Help & support', [
              body('Questions, problems signing in, or feedback on the app? We\'re happy to help.'),
              Card(
                child: ListTile(
                  leading: Icon(Icons.mail_outline_rounded, color: context.colors.primary),
                  title: const SelectableText(AppConfig.supportEmail),
                  subtitle: const Text('Email support'),
                  onTap: () => _email(context),
                  trailing: IconButton(
                    tooltip: 'Copy email address',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => _copy(context),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in const [('help', 'Help & FAQs'), ('terms', 'Terms of Use'), ('privacy', 'Privacy Policy')])
                OutlinedButton(onPressed: () => context.push('/pages/${p.$1}'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)), child: Text(p.$2)),
            ]),
            const SizedBox(height: 24),
            Text('Version ${AppConfig.version}', style: context.text.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}
