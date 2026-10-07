import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/job_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_logo.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'job_list_sliver.dart';

class CompanyScreen extends ConsumerWidget {
  const CompanyScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider);
    final jobs = ref.watch(companyJobsProvider(companyId));
    Company? company;
    for (final c in companies.value?.data ?? const <Company>[]) {
      if (c.id == companyId) company = c;
    }
    company ??= jobs.jobs.isNotEmpty ? jobs.jobs.first.company : null;
    final pad = pagePadding(context);

    return Scaffold(
      appBar: AppBar(title: Text(company?.name ?? 'Company')),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(companiesProvider.notifier).refresh(),
            ref.read(companyJobsProvider(companyId).notifier).refresh(),
          ]);
        },
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverPadding(
            padding: pad.copyWith(top: 8),
            sliver: SliverToBoxAdapter(
              child: company == null
                  ? (companies.isLoading ? const ProfileSkeleton() : const SizedBox())
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CompanyLogo(company: company, size: 72),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(company.name, style: context.text.headlineSmall)),
                              if (company.verified) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.verified_rounded, color: context.colors.primary, semanticLabel: 'Verified employer'),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            Text('${company.industry.label} · ${company.location}', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Text(company.about, style: context.text.bodyLarge),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        TagChip(company.size, icon: Icons.groups_outlined),
                        TagChip('Founded ${company.founded}', icon: Icons.history_edu_outlined),
                        TagChip(company.website, icon: Icons.language_rounded),
                      ]),
                      const SizedBox(height: 28),
                      SectionHeader('Open jobs', subtitle: jobs.loading ? null : '${jobs.total ?? jobs.jobs.length} open roles'),
                      const SizedBox(height: 12),
                    ]),
            ),
          ),
          if (jobs.loading)
            SliverPadding(padding: pad, sliver: const SliverToBoxAdapter(child: JobListSkeleton(count: 2)))
          else if (jobs.error != null)
            SliverToBoxAdapter(child: ErrorState(error: jobs.error!, onRetry: () => ref.read(companyJobsProvider(companyId).notifier).refresh()))
          else if (jobs.jobs.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(icon: Icons.work_off_outlined, title: 'No open jobs', message: 'This employer has no open roles right now.'),
            )
          else ...[
            SliverPadding(padding: pad, sliver: JobListSliver(jobs: jobs.jobs)),
            SliverToBoxAdapter(
              child: LoadMoreFooter(
                loading: jobs.loadingMore,
                hasMore: jobs.hasMore,
                error: jobs.loadMoreError,
                onRetry: () => ref.read(companyJobsProvider(companyId).notifier).loadMore(),
              ),
            ),
            if (jobs.hasMore && !jobs.loadingMore)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: () => ref.read(companyJobsProvider(companyId).notifier).loadMore(),
                    child: const Text('Show more jobs'),
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ]),
      ),
    );
  }
}
