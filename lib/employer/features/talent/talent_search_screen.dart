import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../providers/hiring_providers.dart';
import '../../../widgets/common.dart';
import '../../../widgets/skeletons.dart';
import '../../../widgets/states.dart';
import '../../providers.dart';
import '../../widgets.dart';
import 'talent_profile_screen.dart';

/// Search job seekers who chose to be found, and invite them to apply.
class TalentSearchScreen extends ConsumerStatefulWidget {
  const TalentSearchScreen({super.key});

  @override
  ConsumerState<TalentSearchScreen> createState() => _TalentSearchScreenState();
}

class _TalentSearchScreenState extends ConsumerState<TalentSearchScreen> {
  final _query = TextEditingController();
  String _location = '';
  Industry? _industry;
  List<TalentProfile>? _results;
  Object? _error;
  bool _loading = false;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(hiringBackendProvider).searchTalent(
            query: _query.text,
            location: _location,
            industry: _industry?.name ?? '',
            offset: append ? (_results?.length ?? 0) : 0,
          );
      setState(() {
        _results = append ? [...?_results, ...page] : page;
        _more = page.length >= 30;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite(TalentProfile p) async {
    final job = await inviteTalent(context, ref, userId: p.userId, name: p.fullName, alreadyInvited: p.invitedJobIds);
    if (job != null && mounted) {
      setState(() => _results = [for (final x in _results ?? const <TalentProfile>[]) x.userId == p.userId ? x.withInvite(job.id) : x]);
    }
  }

  Future<void> _open(TalentProfile p) async {
    await context.push('/employer/talent/${p.userId}', extra: p.invitedJobIds);
    // Invitations sent from the profile show on the list too.
    if (mounted) _search();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(employerJobsProvider).value?.data ?? const <Job>[];
    final results = _results;
    return EmployerPage(
      title: 'Find talent',
      subtitle: 'Job seekers who chose to be found. Their phone, email and CV stay private until they apply.',
      onRefresh: () => _search(),
      children: [
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(hintText: 'Skill or job title, e.g. accountant', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: _location,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Location', isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('Anywhere')),
                for (final l in sierraLeoneLocations) DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) {
                setState(() => _location = v ?? '');
                _search();
              },
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<Industry?>(
              initialValue: _industry,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Wants to work in', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Any field')),
                for (final i in Industry.values) DropdownMenuItem(value: i, child: Text(i.label)),
              ],
              onChanged: (v) {
                setState(() => _industry = v);
                _search();
              },
            ),
          ),
          FilledButton.icon(onPressed: _loading ? null : () => _search(), icon: const Icon(Icons.search_rounded), label: const Text('Search')),
        ]),
        const SizedBox(height: 16),
        if (_error != null)
          ErrorState(error: _error!, onRetry: () => _search())
        else if (results == null)
          const Skeleton(child: Column(children: [ListTileSkeleton(), ListTileSkeleton(), ListTileSkeleton()]))
        else if (results.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.person_search_outlined,
              title: 'No one matches yet',
              message: 'Try fewer words or another location. More people appear as job seekers choose to be found.',
            ),
          )
        else ...[
          Text('${results.length}${_more ? '+' : ''} ${results.length == 1 ? 'person' : 'people'}', style: context.text.titleSmall),
          const SizedBox(height: 8),
          for (final p in results) _TalentCard(person: p, jobs: jobs, onInvite: () => _invite(p), onOpen: () => _open(p)),
          if (_more)
            Center(
              child: TextButton(onPressed: _loading ? null : () => _search(append: true), child: const Text('Show more')),
            ),
        ],
      ],
    );
  }
}

class _TalentCard extends StatelessWidget {
  const _TalentCard({required this.person, required this.jobs, required this.onInvite, required this.onOpen});
  final TalentProfile person;
  final List<Job> jobs;
  final VoidCallback onInvite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final muted = context.palette.muted;
    final invitedTo = [for (final j in jobs) if (p.invitedJobIds.contains(j.id)) j.title];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UserAvatar(initials: p.initials, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.fullName, style: context.text.titleMedium),
                if (p.headline.isNotEmpty) Text(p.headline, style: context.text.bodyMedium),
                Text(
                  [if (p.location.isNotEmpty) p.location, if (p.updatedAt != null) 'Profile updated ${Fmt.ago(p.updatedAt!).toLowerCase()}'].join(' · '),
                  style: context.text.bodySmall?.copyWith(color: muted),
                ),
              ]),
            ),
          ]),
          if (p.about.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(p.about, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
          ],
          if (p.skills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in p.skills.take(10)) TagChip(s, dense: true)]),
          ],
          if (p.experience.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Experience', style: context.text.labelLarge),
            for (final e in p.experience) Text(e, style: context.text.bodySmall),
          ],
          if (p.education.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Education', style: context.text.labelLarge),
            for (final e in p.education) Text(e, style: context.text.bodySmall),
          ],
          if (p.languages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Languages: ${p.languages.join(', ')}', style: context.text.bodySmall?.copyWith(color: muted)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: onOpen, icon: const Icon(Icons.person_outline_rounded, size: 18), label: const Text('View full profile')),
            FilledButton.tonalIcon(onPressed: onInvite, icon: const Icon(Icons.mark_email_unread_outlined, size: 18), label: const Text('Invite to apply')),
            if (invitedTo.isNotEmpty)
              Text('Invited to: ${invitedTo.join(', ')}', style: context.text.bodySmall?.copyWith(color: AppColors.green, fontWeight: FontWeight.w600)),
          ]),
        ]),
        ),
      ),
    );
  }
}
