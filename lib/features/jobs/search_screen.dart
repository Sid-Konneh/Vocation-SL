import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/job_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'filter_sheet.dart';
import 'job_list_sliver.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialFilter});
  final JobFilter? initialFilter;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFilter ?? JobFilter.empty;
    _query.text = initial.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchProvider.notifier).setFilter(initial);
      if (widget.initialFilter == null) _focus.requestFocus();
    });
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) ref.read(searchProvider.notifier).loadMore();
    });
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => ref.read(searchProvider.notifier).setQuery(q));
  }

  void _submit(String q) {
    _debounce?.cancel();
    ref.read(searchProvider.notifier).setQuery(q);
    ref.read(recentSearchesProvider.notifier).add(q);
    _focus.unfocus();
  }

  void _apply(JobFilter f) => ref.read(searchProvider.notifier).setFilter(f);

  Future<void> _openFilters() async {
    final f = await showFilterSheet(context, ref.read(searchProvider).filter);
    if (f != null) _apply(f);
  }

  Future<void> _saveSearch(JobFilter filter) async {
    final result = await showDialog<(String, AlertFrequency)>(context: context, builder: (_) => _SaveSearchDialog(filter: filter));
    if (result == null || !mounted) return;
    try {
      await ref.read(alertsProvider.notifier).create(result.$1, filter, result.$2);
      if (mounted) showSnack(context, 'Search saved. We\'ll alert you about new matches.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(searchProvider);
    final f = s.filter;
    final recent = ref.watch(recentSearchesProvider);
    final showRecent = _focus.hasFocus && _query.text.isEmpty && recent.isNotEmpty;
    final pad = pagePadding(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _query,
            focusNode: _focus,
            onChanged: _onChanged,
            onSubmitted: _submit,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Job title, skill or company',
              prefixIcon: const Icon(Icons.search_rounded),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide(color: context.colors.primary)),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _query.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              isLabelVisible: f.activeCount > 0,
              label: Text('${f.activeCount}'),
              child: IconButton.outlined(tooltip: 'Filters', onPressed: _openFilters, icon: const Icon(Icons.tune_rounded)),
            ),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            padding: pad.copyWith(top: 8, bottom: 8),
            scrollDirection: Axis.horizontal,
            children: [
              _QuickChip(
                label: 'Remote',
                selected: f.workModes.contains(WorkMode.remote),
                onTap: () => _apply(f.copyWith(workModes: _flip(f.workModes, WorkMode.remote))),
              ),
              _QuickChip(
                label: 'Full-time',
                selected: f.employmentTypes.contains(EmploymentType.fullTime),
                onTap: () => _apply(f.copyWith(employmentTypes: _flip(f.employmentTypes, EmploymentType.fullTime))),
              ),
              for (final loc in const ['Freetown', 'Bo', 'Kenema', 'Makeni', 'Port Loko'])
                _QuickChip(label: loc, selected: f.locations.contains(loc), onTap: () => _apply(f.copyWith(locations: _flip(f.locations, loc)))),
              _QuickChip(
                label: 'Past week',
                selected: f.datePosted == DatePosted.week,
                onTap: () => _apply(f.copyWith(datePosted: f.datePosted == DatePosted.week ? DatePosted.any : DatePosted.week)),
              ),
              _QuickChip(
                label: 'Entry level',
                selected: f.experienceLevels.contains(ExperienceLevel.entry),
                onTap: () => _apply(f.copyWith(experienceLevels: _flip(f.experienceLevels, ExperienceLevel.entry))),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: showRecent
              ? _RecentSearches(
                  items: recent,
                  onTap: (q) {
                    _query.text = q;
                    _submit(q);
                  },
                  onClear: () => ref.read(recentSearchesProvider.notifier).clear(),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(searchProvider.notifier).refresh(),
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: pad.copyWith(top: 16, bottom: 12),
                        sliver: SliverToBoxAdapter(
                          child: Row(children: [
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  s.loading
                                      ? 'Searching…'
                                      : '${s.total ?? s.jobs.length}${s.hasMore && s.total == null ? '+' : ''} job${(s.total ?? s.jobs.length) == 1 ? '' : 's'}',
                                  style: context.text.titleMedium,
                                ),
                              ),
                            ),
                            PopupMenuButton<JobSort>(
                              tooltip: 'Sort',
                              initialValue: f.sort,
                              onSelected: (v) => _apply(f.copyWith(sort: v)),
                              itemBuilder: (_) => [for (final v in JobSort.values) PopupMenuItem(value: v, child: Text(v.label))],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(children: [
                                  Icon(Icons.swap_vert_rounded, size: 18, color: context.palette.muted),
                                  const SizedBox(width: 4),
                                  Text(f.sort.label, style: context.text.labelLarge),
                                ]),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      if (!f.isEmpty && !s.loading && s.error == null)
                        SliverPadding(
                          padding: pad.copyWith(bottom: 12),
                          sliver: SliverToBoxAdapter(
                            child: OutlinedButton.icon(
                              onPressed: () => _saveSearch(f),
                              icon: const Icon(Icons.notifications_active_outlined, size: 20),
                              label: const Text('Save search & get alerts'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                            ),
                          ),
                        ),
                      if (s.offlineCopy && s.jobs.isNotEmpty)
                        SliverPadding(
                          padding: pad,
                          sliver: SliverToBoxAdapter(
                            child: CacheNotice(syncedAt: s.syncedAt, onRetry: () => ref.read(searchProvider.notifier).refresh()),
                          ),
                        ),
                      if (s.loading)
                        SliverPadding(padding: pad, sliver: const SliverToBoxAdapter(child: JobListSkeleton(count: 5)))
                      else if (s.error != null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: ErrorState(error: s.error!, onRetry: () => ref.read(searchProvider.notifier).refresh()),
                        )
                      else if (s.jobs.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'No matching jobs',
                            message: f.activeCount > 0
                                ? 'Try removing some filters or searching for a broader term.'
                                : 'Try a different job title, skill or company name.',
                            action: f.activeCount > 0 ? 'Clear filters' : null,
                            onAction: () => _apply(f.clearFilters()),
                          ),
                        )
                      else ...[
                        SliverPadding(padding: pad, sliver: JobListSliver(jobs: s.jobs)),
                        SliverToBoxAdapter(
                          child: LoadMoreFooter(
                            loading: s.loadingMore,
                            hasMore: s.hasMore,
                            error: s.loadMoreError,
                            onRetry: () => ref.read(searchProvider.notifier).loadMore(),
                            endLabel: 'End of results',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  Set<T> _flip<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: context.colors.onSurface,
          labelStyle: context.text.labelLarge?.copyWith(color: selected ? context.colors.surface : context.colors.onSurface),
          side: BorderSide(color: selected ? context.colors.onSurface : context.palette.border),
        ),
      );
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.items, required this.onTap, required this.onClear});
  final List<String> items;
  final void Function(String) onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListView(padding: pagePadding(context).copyWith(top: 12), children: [
        Row(children: [
          Expanded(child: Text('Recent searches', style: context.text.titleMedium)),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ]),
        for (final q in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded),
            title: Text(q),
            trailing: const Icon(Icons.north_west_rounded, size: 18),
            onTap: () => onTap(q),
          ),
      ]);
}

class _SaveSearchDialog extends StatefulWidget {
  const _SaveSearchDialog({required this.filter});
  final JobFilter filter;

  @override
  State<_SaveSearchDialog> createState() => _SaveSearchDialogState();
}

class _SaveSearchDialogState extends State<_SaveSearchDialog> {
  late final _name = TextEditingController(text: widget.filter.summary.replaceAll('"', ''));
  AlertFrequency _freq = AlertFrequency.daily;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Save this search'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.filter.summary, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 16),
          Text('Alert me', style: context.text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<AlertFrequency>(
            segments: [for (final f in AlertFrequency.values) ButtonSegment(value: f, label: Text(f.label))],
            selected: {_freq},
            onSelectionChanged: (s) => setState(() => _freq = s.first),
            showSelectedIcon: false,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.pop(context, (_name.text, _freq)),
            child: const Text('Save'),
          ),
        ],
      );
}
