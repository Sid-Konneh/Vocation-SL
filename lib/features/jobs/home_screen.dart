import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/job_providers.dart';
import '../../providers/session_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/job_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'job_list_sliver.dart';

const _industryShort = {
  Industry.technology: 'Tech',
  Industry.healthcare: 'Health',
  Industry.finance: 'Finance',
  Industry.education: 'Education',
  Industry.ngo: 'NGOs',
  Industry.government: 'Public',
  Industry.agriculture: 'Farming',
  Industry.engineering: 'Engineering',
  Industry.energy: 'Energy',
  Industry.logistics: 'Logistics',
};

const _industryIcons = {
  Industry.technology: Icons.computer_rounded,
  Industry.healthcare: Icons.local_hospital_outlined,
  Industry.finance: Icons.account_balance_outlined,
  Industry.education: Icons.school_outlined,
  Industry.ngo: Icons.volunteer_activism_outlined,
  Industry.government: Icons.account_balance_wallet_outlined,
  Industry.agriculture: Icons.agriculture_outlined,
  Industry.engineering: Icons.engineering_outlined,
  Industry.energy: Icons.solar_power_outlined,
  Industry.logistics: Icons.local_shipping_outlined,
};

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) ref.read(homeFeedProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _search([JobFilter? f]) => context.push('/search', extra: f);

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(homeFeedProvider);
    final user = ref.watch(profileProvider).value?.data;
    final pad = pagePadding(context);
    final featured = feed.jobs.where((j) => j.featured).toList();
    final recommended = _recommend(feed.jobs, user);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(homeFeedProvider.notifier).refresh(),
            ref.read(savedJobsProvider.notifier).refresh(),
          ]);
        },
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverPadding(
                padding: pad.copyWith(top: 16),
                sliver: SliverToBoxAdapter(child: _Header(user: user, onSearch: _search)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: pad.copyWith(top: 16, bottom: 4),
                  scrollDirection: Axis.horizontal,
                  itemCount: Industry.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 18),
                  itemBuilder: (_, i) {
                    final ind = Industry.values[i];
                    return _CategoryButton(
                      icon: _industryIcons[ind]!,
                      label: _industryShort[ind]!,
                      onTap: () => _search(JobFilter(industries: {ind})),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider()),
            if (feed.offlineCopy && feed.jobs.isNotEmpty)
              SliverPadding(
                padding: pad.copyWith(top: 12),
                sliver: SliverToBoxAdapter(
                  child: CacheNotice(syncedAt: feed.syncedAt, onRetry: () => ref.read(homeFeedProvider.notifier).refresh()),
                ),
              ),
            if (featured.isNotEmpty) ...[
              SliverPadding(
                padding: pad.copyWith(top: 24, bottom: 12),
                sliver: const SliverToBoxAdapter(child: SectionHeader('Featured jobs', subtitle: 'Top roles from verified employers')),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 184,
                  child: ListView.separated(
                    padding: pad,
                    scrollDirection: Axis.horizontal,
                    itemCount: featured.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SizedBox(width: 290, child: FeaturedJobCard(job: featured[i])),
                  ),
                ),
              ),
            ],
            if (recommended.isNotEmpty) ...[
              SliverPadding(
                padding: pad.copyWith(top: 28, bottom: 12),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    'Recommended for you',
                    subtitle: 'Based on your skills and preferences',
                    action: 'See all',
                    onAction: () => _search(JobFilter(
                      industries: user?.preferences.industries ?? const {},
                      locations: user?.preferences.locations ?? const {},
                    )),
                  ),
                ),
              ),
              SliverPadding(padding: pad, sliver: JobListSliver(jobs: recommended)),
            ],
            SliverPadding(
              padding: pad.copyWith(top: 28, bottom: 12),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  'Latest jobs',
                  subtitle: feed.total != null ? '${feed.total} open roles across Sierra Leone' : 'Open roles across Sierra Leone',
                  action: 'Search',
                  onAction: _search,
                ),
              ),
            ),
            if (feed.loading)
              SliverPadding(padding: pad, sliver: const SliverToBoxAdapter(child: JobListSkeleton()))
            else if (feed.error != null)
              SliverToBoxAdapter(child: ErrorState(error: feed.error!, onRetry: () => ref.read(homeFeedProvider.notifier).refresh()))
            else if (feed.jobs.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(icon: Icons.work_off_outlined, title: 'No jobs yet', message: 'New roles are posted every day. Check back soon.'),
              )
            else ...[
              SliverPadding(padding: pad, sliver: JobListSliver(jobs: feed.jobs, showDescription: true)),
              SliverToBoxAdapter(
                child: LoadMoreFooter(
                  loading: feed.loadingMore,
                  hasMore: feed.hasMore,
                  error: feed.loadMoreError,
                  onRetry: () => ref.read(homeFeedProvider.notifier).loadMore(),
                  endLabel: 'You\'ve seen all ${feed.jobs.length} jobs',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Job> _recommend(List<Job> jobs, AppUser? user) {
    if (user == null || jobs.isEmpty) return const [];
    final skills = user.skills.map((s) => s.toLowerCase()).toSet();
    final prefs = user.preferences;
    int score(Job j) {
      var s = j.skills.where((k) => skills.contains(k.toLowerCase())).length * 3;
      if (prefs.industries.contains(j.industry)) s += 2;
      if (prefs.locations.contains(j.location)) s += 1;
      if (prefs.workModes.contains(j.workMode)) s += 1;
      if (prefs.titles.any((t) => j.title.toLowerCase().contains(t.toLowerCase().split(' ').first))) s += 3;
      return s;
    }

    final scored = jobs.where((j) => !j.isClosed).map((j) => (j, score(j))).where((e) => e.$2 >= 4).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(3).map((e) => e.$1).toList();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user, required this.onSearch});
  final AppUser? user;
  final void Function([JobFilter?]) onSearch;

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user == null ? _greeting : '$_greeting, ${user!.firstName}',
                  style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 2),
              Text('Find your next role', style: context.text.headlineMedium),
            ]),
          ),
          if (user != null)
            Semantics(
              button: true,
              label: 'Open profile',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go('/profile'),
                child: UserAvatar(initials: user!.initials, photoBase64: user!.photoBase64, size: 46),
              ),
            ),
        ]),
        const SizedBox(height: 18),
        Semantics(
          button: true,
          label: 'Search jobs by title, skill or company',
          child: Material(
            color: context.colors.surface,
            elevation: 3,
            shadowColor: context.palette.shadow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100), side: BorderSide(color: context.palette.border)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onSearch,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                child: Row(children: [
                  const Icon(Icons.search_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Search jobs', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Title, skill or company · anywhere in Salone',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                    ]),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.palette.border)),
                    child: const Icon(Icons.tune_rounded, size: 20),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]);
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Browse $label jobs',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 80,
            child: Column(children: [
              Icon(icon, size: 26, color: context.colors.onSurface),
              const SizedBox(height: 8),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
            ]),
          ),
        ),
      );
}
