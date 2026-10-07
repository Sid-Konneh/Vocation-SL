import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

const _titles = {'help': 'Help & FAQs', 'terms': 'Terms of Use', 'privacy': 'Privacy Policy'};

/// Help, Terms and Privacy pages, written by admins in Content management.
class SitePageScreen extends ConsumerWidget {
  const SitePageScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(sitePageProvider(slug));
    return Scaffold(
      appBar: AppBar(title: Text(page.value?.title ?? _titles[slug] ?? 'Page')),
      body: ResponsiveCenter(
        maxWidth: AppSpacing.maxReadingWidth,
        child: page.when(
          loading: () => const SingleChildScrollView(child: JobDetailSkeleton()),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(sitePageProvider(slug))),
          data: (p) {
            if (p == null || p.body.trim().isEmpty) {
              return EmptyState(
                icon: Icons.article_outlined,
                title: 'This page hasn\'t been published yet',
                message: 'Questions in the meantime? Email ${AppConfig.supportEmail}.',
              );
            }
            final blocks = p.body.split(RegExp(r'\n\s*\n'));
            return ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
              for (final b in blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: b.trimLeft().startsWith('# ')
                      ? Semantics(header: true, child: Text(b.trimLeft().substring(2).trim(), style: context.text.titleLarge))
                      : SelectableText(b.trim(), style: context.text.bodyLarge),
                ),
              if (p.updatedAt != null)
                Text('Last updated ${Fmt.date(p.updatedAt!)}', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]);
          },
        ),
      ),
    );
  }
}
